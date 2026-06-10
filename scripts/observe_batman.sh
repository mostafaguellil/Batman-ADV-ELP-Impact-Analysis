#!/usr/bin/env bash
set -euo pipefail

# Observe BATMAN-Adv behavior on a mesh node.
#
# Usage:
#   ./scripts/observe_batman.sh [node] [mode] [duration_secs]
#
# Modes:
#   all       — interfaces + neighbors + routes + sysfs (default)
#   neighbors — batctl n (ELP neighbor table)
#   routes    — batctl o (OGM routing table)
#   traffic   — live tcpdump BATMAN/ELP frames (0x4305)
#   watch     — refresh neighbors/routes every 3s

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lab_config.sh
source "${ROOT}/scripts/lab_config.sh"
# shellcheck source=scripts/mesh_fault_lib.sh
source "${ROOT}/scripts/mesh_fault_lib.sh"
# shellcheck source=scripts/mesh_metrics_lib.sh
source "${ROOT}/scripts/mesh_metrics_lib.sh"

NODE="${1:-${LAB_CLIENT_NODE}}"
MODE="${2:-all}"
DURATION="${3:-15}"

require_docker

if ! docker container inspect "${NODE}" >/dev/null 2>&1; then
  echo "ERROR: container '${NODE}' not found. Run ./scripts/start_lab.sh" >&2
  exit 1
fi

print_header() {
  echo "========================================"
  echo " BATMAN-Adv observer — ${NODE}"
  echo " $(date '+%F %T')"
  echo "========================================"
}

show_interfaces() {
  echo ""
  echo ">> Hard interfaces (batctl if)"
  run_in_node "${NODE}" "batctl if 2>/dev/null" || echo "(batctl unavailable — fallback mode?)"
  run_in_node "${NODE}" "ip -4 addr show bat0 2>/dev/null" || true
}

show_neighbors() {
  echo ""
  echo ">> Neighbors — ELP (batctl n)"
  echo "   Voisins detectes par ELP; disparition = lien perdu / noeud parti."
  run_in_node "${NODE}" "batctl n 2>/dev/null" || true
  echo "   count: $(count_neighbors "${NODE}")"
}

show_routes() {
  echo ""
  echo ">> Originators / routes (batctl o)"
  echo "   Table de routage OGM; chemins vers chaque originateur du mesh."
  run_in_node "${NODE}" "batctl o 2>/dev/null" || true
  echo "   count: $(count_originators "${NODE}")"
}

show_sysfs() {
  echo ""
  echo ">> Kernel mesh params (sysfs)"
  for key in elp_interval ogm_interval hop_penalty bridge_loop_avoidance; do
    val="$(read_batman_sysfs "${NODE}" "${key}")"
    echo "   ${key}: ${val}"
  done
}

show_traffic() {
  echo ""
  echo ">> BATMAN/ELP traffic on ${MESH_IFACE} (${DURATION}s, ethertype 0x4305)"
  echo "   Chaque ligne = une trame de controle (OGM + ELP + autres BATMAN)."
  run_in_node "${NODE}" \
    "timeout ${DURATION} tcpdump -i ${MESH_IFACE} -nn -vv ether proto ${BATMAN_ETHERTYPE} 2>/dev/null | head -40" || true
  local pkts
  pkts="$(count_batman_traffic "${NODE}" "${DURATION}")"
  echo "   total_packets_${DURATION}s: ${pkts} ($(batman_pps "${pkts}" "${DURATION}") pps)"
}

show_watch() {
  echo "Watching neighbors/routes every 3s (Ctrl+C to stop)…"
  while true; do
    clear
    print_header
    show_neighbors
    show_routes
    sleep 3
  done
}

usage() {
  cat <<EOF
Observe BATMAN-Adv behavior

Usage:
  $0 [node] [mode] [duration_secs]

Modes:
  all        interfaces + neighbors + routes + sysfs (default)
  neighbors  batctl n — table ELP
  routes     batctl o — table OGM
  traffic    tcpdump live BATMAN frames
  watch      refresh neighbors/routes every 3s

Examples:
  $0 node1 all
  $0 node1 neighbors
  $0 node1 traffic 30
  $0 node15 watch

Pendant un random walk, lancer dans un autre terminal:
  $0 node1 watch
EOF
}

case "${MODE}" in
  -h|--help) usage; exit 0 ;;
  all)
    print_header
    show_interfaces
    show_neighbors
    show_routes
    show_sysfs
    ;;
  neighbors)
    print_header
    show_neighbors
    ;;
  routes)
    print_header
    show_routes
    ;;
  traffic)
    print_header
    show_traffic
    ;;
  watch)
    show_watch
    ;;
  *)
    echo "ERROR: unknown mode '${MODE}'" >&2
    usage
    exit 1
    ;;
esac
