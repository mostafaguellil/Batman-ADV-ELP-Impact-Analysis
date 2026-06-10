#!/usr/bin/env bash
set -euo pipefail

# Random-walk churn with automated ELP/BATMAN + performance analysis.
#
# Usage:
#   ./scripts/mesh_random_walk.sh [steps] [down_secs] [up_secs] [capture_secs]
#
# Examples:
#   ./scripts/mesh_random_walk.sh
#   ./scripts/mesh_random_walk.sh 30 10 10 5

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lab_config.sh
source "${ROOT}/scripts/lab_config.sh"
# shellcheck source=scripts/mesh_fault_lib.sh
source "${ROOT}/scripts/mesh_fault_lib.sh"
# shellcheck source=scripts/mesh_metrics_lib.sh
source "${ROOT}/scripts/mesh_metrics_lib.sh"

STEPS="${1:-20}"
DOWN_SECS="${2:-10}"
UP_SECS="${3:-10}"
CAPTURE_SECS="${4:-5}"
PING_COUNT="${PING_COUNT:-10}"
IPERF_SECS="${IPERF_SECS:-5}"

CLIENT_NODE="${LAB_CLIENT_NODE}"
SERVER_NODE="${LAB_SERVER_NODE}"
SERVER_IP="$(lab_server_ip)"

LOG_DIR="${ROOT}/results"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="${LOG_DIR}/mesh_random_walk_${TS}.log"
CSV="${LOG_DIR}/mesh_random_walk_${TS}.csv"

mkdir -p "${LOG_DIR}"

log() {
  echo "[$(date '+%F %T')] $*" | tee -a "${OUT}"
}

log_batman_state() {
  local label="$1"
  local node="$2"
  log "--- BATMAN state: ${label} (${node}) ---"
  run_in_node "${node}" "batctl if 2>/dev/null; batctl n 2>/dev/null; batctl o 2>/dev/null" | tee -a "${OUT}" || true
  local elp ogm
  elp="$(read_batman_sysfs "${node}" "elp_interval")"
  ogm="$(read_batman_sysfs "${node}" "ogm_interval")"
  log "sysfs: elp_interval=${elp} ogm_interval=${ogm}"
}

record_snapshot() {
  local step="$1"
  local target_node="$2"
  local phase="$3"
  local line

  line="$(collect_mesh_snapshot "${CLIENT_NODE}" "${SERVER_IP}" "${CAPTURE_SECS}" "${PING_COUNT}" "${IPERF_SECS}")"
  echo "${step},${target_node},${phase},${line}" >>"${CSV}"
  log "CSV ${phase}: step=${step} node=${target_node} ${line}"
}

cleanup() {
  log "Cleanup: reconnecting all MANET nodes"
  mesh_reconnect_all
  run_in_node "${SERVER_NODE}" "pkill iperf3 >/dev/null 2>&1 || true" || true
}
trap cleanup EXIT

usage() {
  cat <<EOF
Random-walk mesh churn + automated ELP/BATMAN analysis

Usage:
  $0 [steps] [down_secs] [up_secs] [capture_secs]

  steps         Random disconnect/reconnect cycles (default: 20)
  down_secs     Time node stays disconnected (default: 10)
  up_secs       Stabilization after reconnect (default: 10)
  capture_secs  tcpdump window for BATMAN/ELP count per snapshot (default: 5)

Outputs:
  ${LOG_DIR}/mesh_random_walk_<ts>.log
  ${LOG_DIR}/mesh_random_walk_<ts>.csv

Summarize:
  ./scripts/summarize_random_walk.sh ${LOG_DIR}/mesh_random_walk_<ts>.csv

Observe BATMAN live:
  ./scripts/observe_batman.sh ${CLIENT_NODE}
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if ! [[ "${STEPS}" =~ ^[0-9]+$ ]] || [[ "${STEPS}" -lt 1 ]]; then
  echo "ERROR: steps must be a positive integer" >&2
  exit 1
fi

require_docker
init_network

for n in "${CLIENT_NODE}" "${SERVER_NODE}"; do
  if ! docker container inspect "${n}" >/dev/null 2>&1; then
    echo "ERROR: container ${n} not found. Run ./scripts/start_lab.sh first." >&2
    exit 1
  fi
done

log "=== Mesh random-walk + ELP analysis started ==="
log "steps=${STEPS}, down_secs=${DOWN_SECS}, up_secs=${UP_SECS}, capture_secs=${CAPTURE_SECS}"
log "network=${MESH_NETWORK}, client=${CLIENT_NODE}, server=${SERVER_NODE}"
log "csv=${CSV}"

echo "step,node,phase,batman_packets,batman_pps,neighbors,originators,ping_avg_ms,ping_loss_pct,throughput_mbps" >"${CSV}"

mesh_reset_all

log "Starting iperf3 server on ${SERVER_NODE}"
run_in_node "${SERVER_NODE}" "pkill iperf3 >/dev/null 2>&1 || true; nohup iperf3 -s >/tmp/iperf3_server.log 2>&1 &"
sleep 2

log_batman_state "baseline" "${CLIENT_NODE}"
record_snapshot "0" "none" "baseline"

last_node=""
for step in $(seq 1 "${STEPS}"); do
  node=""
  attempts=0
  while [[ -z "${node}" && "${attempts}" -lt 10 ]]; do
    candidate="$(pick_random_candidate)"
    if [[ "${candidate}" != "${last_node}" || "${#MESH_RANDOM_CANDIDATES[@]}" -eq 1 ]]; then
      node="${candidate}"
    fi
    attempts=$((attempts + 1))
  done
  [[ -n "${node}" ]] || node="$(pick_random_candidate)"

  log ""
  log "=== STEP ${step}/${STEPS}: disconnect ${node} ==="
  mesh_disconnect "${node}"
  sleep "${DOWN_SECS}"

  log_batman_state "during_disconnect" "${CLIENT_NODE}"
  record_snapshot "${step}" "${node}" "during_disconnect"

  log "=== STEP ${step}/${STEPS}: reconnect ${node} ==="
  mesh_reconnect "${node}"
  sleep "${UP_SECS}"

  log_batman_state "after_reconnect" "${CLIENT_NODE}"
  record_snapshot "${step}" "${node}" "after_reconnect"

  last_node="${node}"
done

trap - EXIT
cleanup

log "=== Random-walk complete ==="
log "Log: ${OUT}"
log "CSV: ${CSV}"

echo ""
"${ROOT}/scripts/summarize_random_walk.sh" "${CSV}"

echo ""
echo "Done."
echo "  Log: ${OUT}"
echo "  CSV: ${CSV}"
