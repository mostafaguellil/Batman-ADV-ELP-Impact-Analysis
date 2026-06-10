#!/usr/bin/env bash
set -euo pipefail

# Deep diagnostics when BATMAN mesh fails in Docker.
# Usage: ./scripts/debug_mesh.sh

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib.sh
source "${ROOT}/scripts/lib.sh"

require_docker

echo "===== BATMAN mesh debug ====="
echo "Host kernel: $(uname -r)"
echo "batman-adv loaded: $(lsmod | grep -c '^batman_adv' || echo 0)"
modinfo batman-adv 2>/dev/null | head -3 || echo "modinfo batman-adv: NOT FOUND"

echo ""
echo "----- Host sysctls (need sudo) -----"
for key in net.bridge.bridge-nf-call-iptables net.ipv4.conf.all.rp_filter; do
  val="$(sysctl -n "${key}" 2>/dev/null || echo '?')"
  echo "  ${key}=${val}"
done

for node in "${NODES[@]}"; do
  echo ""
  echo "===== ${node} ====="
  if ! docker container inspect "${node}" >/dev/null 2>&1; then
    echo "  container not running"
    continue
  fi
  run_in_node "${node}" "
    echo '--- lsmod (container view) ---'
    lsmod 2>/dev/null | grep batman || echo 'batman_adv not in container lsmod'
    echo '--- batctl interface ---'
    batctl meshif bat0 interface 2>&1 || true
    echo '--- batctl n ---'
    batctl meshif bat0 n 2>&1 || true
    echo '--- batctl o ---'
    batctl meshif bat0 o 2>&1 || true
    echo '--- ip addr ---'
    ip -4 addr show dev ${MESH_IFACE}
    ip -4 addr show dev bat0 2>/dev/null || echo 'no bat0'
    echo '--- BATMAN frames on ${MESH_IFACE} (5s) ---'
    timeout 5 tcpdump -i ${MESH_IFACE} -nn -c 5 ether proto ${BATMAN_ETHERTYPE} 2>&1 || echo 'no batman traffic seen'
  "
done

echo ""
echo "----- Docker network (manet) -----"
init_network 2>/dev/null || true
if [[ -n "${MESH_NETWORK:-}" ]]; then
  driver="$(docker network inspect "${MESH_NETWORK}" --format '{{.Driver}}' 2>/dev/null || echo '?')"
  parent="$(docker network inspect "${MESH_NETWORK}" --format '{{index .Options "parent"}}' 2>/dev/null || echo '?')"
  echo "  driver=${driver} parent=${parent}"
  if [[ "${driver}" == "bridge" ]]; then
    net_id="$(docker network inspect "${MESH_NETWORK}" --format '{{.Id}}' 2>/dev/null || true)"
    br_if="br-${net_id:0:12}"
    if [[ -d "/sys/class/net/${br_if}/bridge" ]]; then
      echo "  bridge=${br_if} multicast_snooping=$(cat "/sys/class/net/${br_if}/bridge/multicast_snooping" 2>/dev/null || echo '?')"
    fi
  fi
fi
ip link show "${MANET_PARENT_IF}" 2>/dev/null || echo "  ${MANET_PARENT_IF}: not found (run ./scripts/start_lab.sh)"

echo ""
echo "----- Quick test from node1 -----"
run_in_node node1 "ping -c 2 -W 1 $(lab_server_ip)" 2>&1 || true
run_in_node node1 "batctl meshif bat0 ping -c 2 $(lab_server_ip)" 2>&1 || true

echo ""
echo "If batctl n is empty and tcpdump shows 0 frames:"
echo "  1) sudo modprobe batman-adv"
echo "  2) Recreate network (bridge tuning needs fresh manet): docker compose down && ./scripts/start_lab.sh"
echo "  3) Check multicast_snooping=0 above; if 1: sudo ./scripts/setup_batman.sh batman --skip-compose"
echo "  4) ./scripts/debug_mesh.sh"
echo ""
echo "If still broken, use fallback (connectivity only, no real BATMAN):"
echo "  ./scripts/setup_batman.sh fallback --skip-compose"
