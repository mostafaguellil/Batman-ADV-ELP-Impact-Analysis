#!/usr/bin/env bash
# Shared mesh fault helpers (sourced by mesh_fault.sh and mesh_random_walk.sh).

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lab_config.sh
source "${ROOT}/scripts/lab_config.sh"

MESH_NETWORK=""

require_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: docker not found." >&2
    exit 1
  fi
  if ! docker info >/dev/null 2>&1; then
    echo "ERROR: cannot connect to Docker daemon." >&2
    exit 1
  fi
}

init_network() {
  MESH_NETWORK="$(resolve_mesh_network "${MESH_NODES[0]}")"
}

require_node() {
  local node="$1"
  if ! is_mesh_node "${node}"; then
    echo "ERROR: '${node}' is not a MANET node. Valid: ${MESH_NODES[*]}" >&2
    exit 1
  fi
  if ! docker container inspect "${node}" >/dev/null 2>&1; then
    echo "ERROR: container '${node}' not found." >&2
    exit 1
  fi
}

node_on_mesh_network() {
  local node="$1"
  docker inspect "${node}" --format '{{range $n, $cfg := .NetworkSettings.Networks}}{{println $n}}{{end}}' \
    | grep -Fx "${MESH_NETWORK}" >/dev/null 2>&1
}

run_in_node() {
  local node="$1"
  shift
  docker exec "${node}" bash -lc "$*"
}

restore_batman_hardif() {
  local node="$1"
  run_in_node "${node}" "
    ip link set ${MESH_IFACE} up
    batctl if add ${MESH_IFACE} 2>/dev/null || true
  "
}

mesh_disconnect() {
  local node="$1"
  require_node "${node}"

  if ! node_on_mesh_network "${node}"; then
    echo "NOTE: ${node} is already disconnected from ${MESH_NETWORK}"
    return 0
  fi

  echo "==> Disconnecting ${node} from ${MESH_NETWORK} (full L2 loss)"
  docker network disconnect "${MESH_NETWORK}" "${node}"
  echo "    BATMAN-adv on ${node} loses underlay ${MESH_IFACE}; neighbors should time out the originator."
}

mesh_reconnect() {
  local node="$1"
  require_node "${node}"

  if node_on_mesh_network "${node}"; then
    echo "NOTE: ${node} is already connected to ${MESH_NETWORK}"
    restore_batman_hardif "${node}"
    return 0
  fi

  echo "==> Reconnecting ${node} to ${MESH_NETWORK}"
  docker network connect "${MESH_NETWORK}" "${node}"
  restore_batman_hardif "${node}"
  echo "    Restored ${MESH_IFACE} and re-added it to bat0 where applicable."
}

mesh_reset_netem_all() {
  local node

  for node in "${MESH_NODES[@]}"; do
    if docker container inspect "${node}" >/dev/null 2>&1; then
      run_in_node "${node}" "tc qdisc del dev ${MESH_IFACE} root" || true
    fi
  done
}

mesh_reconnect_all() {
  local node

  echo "==> Reconnecting any disconnected MANET nodes"
  for node in "${MESH_NODES[@]}"; do
    if docker container inspect "${node}" >/dev/null 2>&1 && ! node_on_mesh_network "${node}"; then
      mesh_reconnect "${node}"
    fi
  done
}

mesh_reset_all() {
  echo "==> Resetting netem on all MANET nodes"
  mesh_reset_netem_all
  mesh_reconnect_all
}

pick_random_candidate() {
  printf '%s\n' "${MESH_RANDOM_CANDIDATES[@]}" | shuf | head -n 1
}

pick_random_candidates() {
  local count="$1"
  printf '%s\n' "${MESH_RANDOM_CANDIDATES[@]}" | shuf | head -n "${count}"
}
