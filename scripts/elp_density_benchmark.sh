#!/usr/bin/env bash
set -euo pipefail

# ELP / BATMAN control traffic and performance vs mesh density.
#
# Usage:
#   ./scripts/elp_density_benchmark.sh [density_list] [capture_secs] [converge_secs]

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lab_config.sh
source "${ROOT}/scripts/lab_config.sh"
# shellcheck source=scripts/mesh_fault_lib.sh
source "${ROOT}/scripts/mesh_fault_lib.sh"
# shellcheck source=scripts/mesh_metrics_lib.sh
source "${ROOT}/scripts/mesh_metrics_lib.sh"

DENSITY_LIST="${1:-5 10 15 20 25 30}"
CAPTURE_SECS="${2:-30}"
CONVERGE_SECS="${3:-45}"
PING_COUNT="${PING_COUNT:-30}"
IPERF_SECS="${IPERF_SECS:-15}"

CLIENT_NODE="${LAB_CLIENT_NODE}"
SERVER_NODE="${LAB_SERVER_NODE}"
SERVER_IP="$(lab_server_ip)"

LOG_DIR="${ROOT}/results"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="${LOG_DIR}/elp_density_${TS}.log"
CSV="${LOG_DIR}/elp_density_${TS}.csv"

mkdir -p "${LOG_DIR}"

log() {
  echo "[$(date '+%F %T')] $*" | tee -a "${OUT}"
}

cleanup() {
  log "Cleanup: restoring full mesh (${NODE_COUNT} nodes)"
  "${ROOT}/scripts/set_mesh_density.sh" "${NODE_COUNT}" >>"${OUT}" 2>&1 || true
  run_in_node "${SERVER_NODE}" "pkill iperf3 >/dev/null 2>&1 || true" || true
}
trap cleanup EXIT

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "WARNING: BATMAN-Adv mode requires Linux. Results will reflect fallback overlay only." | tee -a "${OUT}"
fi

require_docker
init_network

log "=== ELP density benchmark started ==="
log "densities=${DENSITY_LIST}, capture_secs=${CAPTURE_SECS}, converge_secs=${CONVERGE_SECS}"
log "csv=${CSV}"

echo "density,batman_packets,batman_pps,neighbor_count,originator_count,ping_avg_ms,ping_loss_pct,throughput_mbps" >"${CSV}"

run_in_node "${SERVER_NODE}" "pkill iperf3 >/dev/null 2>&1 || true; nohup iperf3 -s >/tmp/iperf3_server.log 2>&1 &"
sleep 2

for density in ${DENSITY_LIST}; do
  [[ "${density}" -ge 1 && "${density}" -le "${NODE_COUNT}" ]] || continue

  log ""
  log "=== DENSITY ${density} ==="
  "${ROOT}/scripts/set_mesh_density.sh" "${density}" >>"${OUT}" 2>&1
  sleep "${CONVERGE_SECS}"

  snapshot="$(collect_mesh_snapshot "${CLIENT_NODE}" "${SERVER_IP}" "${CAPTURE_SECS}" "${PING_COUNT}" "${IPERF_SECS}")"
  echo "${density},${snapshot}" >>"${CSV}"
  log "density=${density} ${snapshot}"

  run_in_node "${CLIENT_NODE}" "batctl n; batctl o" >>"${OUT}" 2>&1 || true
done

trap - EXIT
cleanup

log "=== Benchmark complete ==="
echo ""
"${ROOT}/scripts/summarize_elp_benchmark.sh" "${CSV}"
echo "  Log: ${OUT}"
echo "  CSV: ${CSV}"
