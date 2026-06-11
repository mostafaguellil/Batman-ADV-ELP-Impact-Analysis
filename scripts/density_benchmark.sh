#!/usr/bin/env bash
set -euo pipefail

# ELP/BATMAN metrics vs mesh density.
# Usage: ./scripts/density_benchmark.sh [densities] [capture_secs] [converge_secs]

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib.sh
source "${ROOT}/scripts/lib.sh"

DENSITY_LIST="${1:-2 5 10 15 20 30}"
CAPTURE_SECS="${2:-15}"
CONVERGE_SECS="${3:-}"  # auto: scales with density if empty
SERVER_IP="$(lab_server_ip)"
LOG_DIR="${ROOT}/results"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="${LOG_DIR}/density_${TS}.log"
CSV="${LOG_DIR}/density_${TS}.csv"

mkdir -p "${LOG_DIR}"
log() { echo "[$(date '+%F %T')] $*" | tee -a "${OUT}"; }

cleanup() {
  set_mesh_density "${NODE_COUNT}" >>"${OUT}" 2>&1 || true
  stop_iperf_server
}
trap cleanup EXIT

require_docker
init_network

echo "density,batman_packets,batman_pps,neighbors,originators,ping_avg_ms,ping_loss_pct,throughput_mbps" >"${CSV}"
start_iperf_server; sleep 2

for density in ${DENSITY_LIST}; do
  [[ "${density}" -ge 1 && "${density}" -le "${NODE_COUNT}" ]] || continue
  log "=== density ${density} ==="
  set_mesh_density "${density}" >>"${OUT}" 2>&1
  converge="${CONVERGE_SECS:-$((10 + density * 2))}"
  (( converge > 60 )) && converge=60
  sleep "${converge}"
  snap="$(collect_mesh_snapshot "${LAB_CLIENT_NODE}" "${SERVER_IP}" "${CAPTURE_SECS}" 15 8)"
  echo "${density},${snap}" >>"${CSV}"
  log "${density},${snap}"
  run_in_node "${LAB_CLIENT_NODE}" "batctl meshif bat0 n; batctl meshif bat0 o" >>"${OUT}" 2>&1 || true
done

trap - EXIT; cleanup
log "CSV: ${CSV}"
"${ROOT}/scripts/summarize_results.sh" density "${CSV}"
