#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib.sh
source "${ROOT}/scripts/lib.sh"

UNDERLAY_IF="${MESH_IFACE}"
OS_NAME="$(uname -s)"
SKIP_COMPOSE=0
POSITIONAL=()

for arg in "$@"; do
  if [[ "${arg}" == "--skip-compose" ]]; then
    SKIP_COMPOSE=1
  else
    POSITIONAL+=("${arg}")
  fi
done

MODE="${POSITIONAL[0]:-auto}" # auto | batman | fallback

require_cmd() {
  local cmd="$1"
  local hint="$2"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "ERROR: '${cmd}' not found."
    echo "Hint: ${hint}"
    exit 1
  fi
}

if [[ "${MODE}" != "auto" && "${MODE}" != "batman" && "${MODE}" != "fallback" ]]; then
  echo "ERROR: Invalid mode '${MODE}'."
  echo "Usage: ./scripts/setup_batman.sh [auto|batman|fallback] [--skip-compose]"
  exit 1
fi

require_cmd docker "Install Docker Engine and ensure the daemon is running."

if ! docker compose version >/dev/null 2>&1; then
  echo "ERROR: 'docker compose' is not available."
  echo "Hint: Install Docker Compose plugin, then retry."
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "ERROR: Cannot connect to Docker daemon."
  echo "Hint: start Docker Desktop/Engine, then retry."
  exit 1
fi

if [[ "${MODE}" == "auto" ]]; then
  if [[ "${OS_NAME}" == "Linux" ]]; then
    MODE="batman"
  else
    MODE="fallback"
  fi
fi

if [[ "${SKIP_COMPOSE}" -eq 0 ]]; then
  if [[ "$(uname -s)" == "Linux" ]]; then
    preflight_ubuntu_batman
  fi
  echo "==> Starting containers"
  for node in "${NODES[@]}"; do
    if docker container inspect "${node}" >/dev/null 2>&1; then
      echo "==> Removing stale container: ${node}"
      docker rm -f "${node}" >/dev/null
    fi
  done
  docker compose build
  docker compose up -d
else
  echo "==> Skipping docker compose (stack assumed already up)"
fi

if [[ "$(uname -s)" == "Linux" ]]; then
  tune_manet_bridge || true
fi

if [[ "${MODE}" == "batman" ]]; then
  if [[ "${OS_NAME}" != "Linux" ]]; then
    echo "WARNING: 'batman' mode requires Linux host kernel."
    echo "Hint: on macOS it cannot load batman-adv; switching to 'fallback' so you can keep testing ping/iperf/tcpdump."
    MODE="fallback"
  else
    require_cmd modprobe "Install kmod package on host and retry."
    if ! modinfo batman-adv >/dev/null 2>&1; then
      echo "ERROR: Kernel module 'batman-adv' not found on the host."
      echo "Hint: sudo apt install linux-modules-extra-\$(uname -r)"
      exit 1
    fi
    if lsmod | grep -q '^batman_adv'; then
      echo "==> batman-adv already loaded on host"
    else
      echo "==> Loading batman-adv module on host (sudo password may be requested)"
      if ! sudo modprobe batman-adv; then
        echo "ERROR: could not load batman-adv on the host."
        echo "Hint: sudo apt install linux-modules-extra-\$(uname -r)"
        echo "      sudo modprobe batman-adv"
        exit 1
      fi
    fi
    ensure_host_batman_prereqs || true
  fi
fi

ensure_container_tools

if [[ "${MODE}" == "batman" ]]; then
  echo "==> Configuring BATMAN-Adv in each node (no IP on ${UNDERLAY_IF}, only bat0)"
  for i in "${!NODES[@]}"; do
    node="${NODES[$i]}"
    bat_ip="${BAT_IPS[$i]}"
    echo "    ${node} -> ${bat_ip}"
    configure_batman_node "${node}" "${bat_ip}"
  done

  MESH_OK=1
  wait_for_mesh_convergence "${LAB_CLIENT_NODE}" $((NODE_COUNT - 1)) 90 || MESH_OK=0

  echo "==> BATMAN interfaces"
  for node in "${NODES[@]}"; do
    echo "--- ${node} ---"
    docker exec "${node}" bash -lc "batctl if && ip -4 addr show ${UNDERLAY_IF} && ip -4 addr show bat0"
  done
else
  echo "==> Fallback mode enabled (no batman-adv module required)"
  echo "==> Assigning test overlay IPs directly on ${UNDERLAY_IF}"
  for i in "${!NODES[@]}"; do
    node="${NODES[$i]}"
    bat_ip="${BAT_IPS[$i]}"
    docker exec "${node}" bash -lc "
      ip link set ${UNDERLAY_IF} up
      ip addr add ${bat_ip} dev ${UNDERLAY_IF} || true
      ip -4 addr show ${UNDERLAY_IF}
    "
  done
fi

echo "==> Connectivity test over ${MESH_SUBNET_PREFIX}.0/24 (${NODE_COUNT} nodes)"
if [[ "${MODE}" == "batman" ]]; then
  if ! mesh_ping_test "${LAB_CLIENT_NODE}" "$(lab_server_ip)" 3; then
    show_mesh_diagnostics "${LAB_CLIENT_NODE}"
    echo ""
    echo "ERROR: BATMAN mesh ping failed."
    echo "Run: ./scripts/debug_mesh.sh"
    echo ""
    echo "Ubuntu checklist:"
    echo "  sudo apt install linux-modules-extra-\$(uname -r) batctl"
    echo "  sudo modprobe batman-adv"
    echo "  docker compose down && ./scripts/start_lab.sh"
    echo ""
    echo "VMware/VirtualBox: enable Promiscuous Mode on the VM network adapter."
    exit 1
  fi
  mesh_ping_test "${LAB_CLIENT_NODE}" "$(lab_last_node_ip)" 3 || show_mesh_diagnostics "${LAB_CLIENT_NODE}"
else
  if ! docker exec node1 bash -lc "ping -c 3 -W 2 $(lab_server_ip)"; then
    echo "ERROR: ping to $(lab_server_ip) failed in fallback mode."
    exit 1
  fi
  docker exec node1 bash -lc "ping -c 3 -W 2 $(lab_last_node_ip)" || true
fi

echo "==> Optional: start iperf3 server on node2"
echo "docker exec -d node2 bash -lc 'iperf3 -s'"
echo "Then run from node1: docker exec node1 bash -lc 'iperf3 -c 10.0.0.2 -t 10'"

if [[ "${MODE}" == "batman" ]]; then
  echo "==> Optional: capture BATMAN packets (includes ELP frames)"
  echo "docker exec node1 bash -lc 'tcpdump -i ${UNDERLAY_IF} -nn -vv ether proto 0x4305'"
  echo "Tip: run batctl in node1 with 'batctl o' and 'batctl n' to observe routes/neighbors."
else
  echo "==> Optional: capture fallback traffic"
  echo "docker exec node1 bash -lc 'tcpdump -i ${UNDERLAY_IF} -nn -vv host 10.0.0.2'"
  echo "Note: fallback mode validates connectivity/perf tooling, not BATMAN-Adv behavior."
fi
