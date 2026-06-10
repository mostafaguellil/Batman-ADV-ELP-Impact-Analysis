#!/usr/bin/env bash
set -euo pipefail

# Usage: ./scripts/observe_batman.sh [node] [mode] [duration]
# Modes: all | neighbors | routes | traffic | watch

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib.sh
source "${ROOT}/scripts/lib.sh"

NODE="${1:-${LAB_CLIENT_NODE}}"
MODE="${2:-all}"
DURATION="${3:-15}"

require_docker
docker container inspect "${NODE}" >/dev/null 2>&1 || { echo "ERROR: ${NODE} not found" >&2; exit 1; }

show_neighbors() {
  echo ">> batctl n (ELP neighbors)"
  run_in_node "${NODE}" "batctl n" 2>/dev/null || true
  echo "count: $(count_neighbors "${NODE}")"
}

show_routes() {
  echo ">> batctl o (OGM routes)"
  run_in_node "${NODE}" "batctl o" 2>/dev/null || true
  echo "count: $(count_originators "${NODE}")"
}

show_traffic() {
  echo ">> BATMAN traffic ${DURATION}s (0x4305)"
  local pkts
  pkts="$(count_batman_traffic "${NODE}" "${DURATION}")"
  run_in_node "${NODE}" "timeout ${DURATION} tcpdump -i ${MESH_IFACE} -nn -q ether proto ${BATMAN_ETHERTYPE} 2>/dev/null | head -20" || true
  echo "packets: ${pkts} ($(batman_pps "${pkts}" "${DURATION}") pps)"
}

case "${MODE}" in
  -h|--help)
    echo "Usage: $0 [node] [all|neighbors|routes|traffic|watch] [duration]"
    exit 0 ;;
  neighbors) show_neighbors ;;
  routes)    show_routes ;;
  traffic)   show_traffic ;;
  watch)
    while true; do clear; echo "=== ${NODE} $(date '+%T') ==="; show_neighbors; show_routes; sleep 3; done ;;
  all|*)
    run_in_node "${NODE}" "batctl if; ip -4 addr show bat0" 2>/dev/null || true
    show_neighbors; show_routes
    echo "elp_interval: $(read_batman_sysfs "${NODE}" elp_interval)"
    echo "ogm_interval: $(read_batman_sysfs "${NODE}" ogm_interval)"
    ;;
esac
