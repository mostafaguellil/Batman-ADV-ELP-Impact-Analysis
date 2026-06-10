#!/usr/bin/env bash
set -euo pipefail

# Random-walk disconnect/reconnect with ELP/BATMAN analysis.
# Usage: ./scripts/random_walk.sh [steps] [down_secs] [up_secs] [capture_secs]

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib.sh
source "${ROOT}/scripts/lib.sh"

STEPS="${1:-20}"
DOWN_SECS="${2:-10}"
UP_SECS="${3:-10}"
CAPTURE_SECS="${4:-5}"
SERVER_IP="$(lab_server_ip)"
LOG_DIR="${ROOT}/results"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="${LOG_DIR}/random_walk_${TS}.log"
CSV="${LOG_DIR}/random_walk_${TS}.csv"

mkdir -p "${LOG_DIR}"
log() { echo "[$(date '+%F %T')] $*" | tee -a "${OUT}"; }

log_batman() {
  local label="$1"
  log "--- ${label} ---"
  run_in_node "${LAB_CLIENT_NODE}" "batctl meshif bat0 interface; batctl meshif bat0 n; batctl meshif bat0 o" >>"${OUT}" 2>&1 || true
}

record() {
  local step="$1" node="$2" phase="$3"
  echo "${step},${node},${phase},$(collect_mesh_snapshot "${LAB_CLIENT_NODE}" "${SERVER_IP}" "${CAPTURE_SECS}" 10 5)" >>"${CSV}"
}

cleanup() { mesh_reconnect_all; stop_iperf_server; }
trap cleanup EXIT

require_docker
init_network

echo "step,node,phase,batman_packets,batman_pps,neighbors,originators,ping_avg_ms,ping_loss_pct,throughput_mbps" >"${CSV}"
mesh_reset_all
start_iperf_server; sleep 2

log_batman "baseline"
record "0" "none" "baseline"

last=""
for step in $(seq 1 "${STEPS}"); do
  node="$(pick_random_candidate)"
  [[ "${node}" != "${last}" || ${#MESH_RANDOM_CANDIDATES[@]} -eq 1 ]] || node="$(pick_random_candidate)"

  log "=== step ${step}: disconnect ${node} ==="
  mesh_disconnect "${node}"
  sleep "${DOWN_SECS}"
  log_batman "during_disconnect"
  record "${step}" "${node}" "during_disconnect"

  log "=== step ${step}: reconnect ${node} ==="
  mesh_reconnect "${node}"
  sleep "${UP_SECS}"
  log_batman "after_reconnect"
  record "${step}" "${node}" "after_reconnect"
  last="${node}"
done

trap - EXIT; cleanup
log "CSV: ${CSV}"
"${ROOT}/scripts/summarize_results.sh" walk "${CSV}"
echo "Done. Log: ${OUT}"
