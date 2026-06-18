#!/usr/bin/env bash
set -euo pipefail

# Random-walk churn: one node disconnected/reconnected at a time with BATMAN metrics.
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
FULL_MESH_NEIGHBORS=$((NODE_COUNT - 1))

mkdir -p "${LOG_DIR}"
log() { echo "[$(date '+%F %T')] $*" | tee -a "${OUT}"; }

log_batman() {
  local label="$1"
  log "--- ${label} ---"
  run_in_node "${LAB_CLIENT_NODE}" "batctl meshif bat0 interface; batctl meshif bat0 n; batctl meshif bat0 o" >>"${OUT}" 2>&1 || true
  log "  neighbors=$(count_neighbors "${LAB_CLIENT_NODE}") originators=$(count_originators "${LAB_CLIENT_NODE}")"
}

record() {
  local step="$1" node="$2" phase="$3"
  local snap nbr pps
  snap="$(collect_mesh_snapshot "${LAB_CLIENT_NODE}" "${SERVER_IP}" "${CAPTURE_SECS}" 10 5)"
  nbr="$(echo "${snap}" | cut -d, -f3)"
  pps="$(echo "${snap}" | cut -d, -f2)"
  echo "${step},${node},${phase},${snap}" >>"${CSV}"
  log "  record: step=${step} node=${node} phase=${phase} neighbors=${nbr} pps=${pps}"
}

preflight_random_walk() {
  echo "==> Random walk preflight"
  if ! docker container inspect "${LAB_CLIENT_NODE}" >/dev/null 2>&1; then
    echo "ERROR: lab not running. Start with: ./scripts/start_lab.sh" >&2
    exit 1
  fi
  if ! run_in_node "${LAB_CLIENT_NODE}" "ip link show bat0 >/dev/null 2>&1"; then
    echo "ERROR: bat0 missing on ${LAB_CLIENT_NODE}. Run: ./scripts/setup_batman.sh" >&2
    exit 1
  fi
}

cleanup() { mesh_reconnect_all; reconcile_batman_hardifs; stop_iperf_server; }
trap cleanup EXIT

require_docker
init_network
preflight_random_walk

echo "step,node,phase,batman_packets,batman_pps,neighbors,originators,ping_avg_ms,ping_loss_pct,throughput_mbps" >"${CSV}"
mesh_reset_all
reconcile_batman_hardifs
start_iperf_server
sleep 2

log "=== baseline: full mesh (${NODE_COUNT} nodes) ==="
wait_for_mesh_convergence "${LAB_CLIENT_NODE}" "${FULL_MESH_NEIGHBORS}" "$(mesh_convergence_timeout "${FULL_MESH_NEIGHBORS}")" \
  >>"${OUT}" 2>&1 || true
finalize_batman_mesh 1

log_batman "baseline"
record "0" "none" "baseline"

last=""
for step in $(seq 1 "${STEPS}"); do
  node="$(pick_random_candidate "${last}")"

  log "=== step ${step}: disconnect ${node} ==="
  mesh_disconnect "${node}"
  want_drop="$(expected_neighbors_for_observer)"
  wait_for_neighbor_drop "${LAB_CLIENT_NODE}" "${want_drop}" "${DOWN_SECS}" >>"${OUT}" 2>&1 || true
  log_batman "during_disconnect"
  record "${step}" "${node}" "during_disconnect"

  log "=== step ${step}: reconnect ${node} ==="
  mesh_reconnect "${node}"
  wait_for_mesh_convergence "${LAB_CLIENT_NODE}" "${FULL_MESH_NEIGHBORS}" "${UP_SECS}" \
    >>"${OUT}" 2>&1 || true
  log_batman "after_reconnect"
  record "${step}" "${node}" "after_reconnect"
  last="${node}"
done

trap - EXIT; cleanup
log "CSV: ${CSV}"
"${ROOT}/scripts/summarize_results.sh" walk "${CSV}"
echo "Done. Log: ${OUT}"
