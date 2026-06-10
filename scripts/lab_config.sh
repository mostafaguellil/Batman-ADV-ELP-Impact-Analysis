#!/usr/bin/env bash
# Shared BATMAN-adv lab topology (sourced by setup/test/fault scripts).

NODE_COUNT=30
MESH_SUBNET_PREFIX="10.0.0"
MESH_IFACE="eth0"
COMPOSE_NETWORK_KEY="manet"

# Stable roles for automated tests (client / iperf server).
LAB_CLIENT_NODE="node1"
LAB_SERVER_NODE="node2"

NODES=()
BAT_IPS=()
MESH_NODES=()
MESH_RANDOM_CANDIDATES=()

for i in $(seq 1 "${NODE_COUNT}"); do
  NODES+=("node${i}")
  BAT_IPS+=("${MESH_SUBNET_PREFIX}.${i}/24")
  MESH_NODES+=("node${i}")
done

# Keep node1/node2 stable; fault random mode uses the rest of the mesh.
for i in $(seq 3 "${NODE_COUNT}"); do
  MESH_RANDOM_CANDIDATES+=("node${i}")
done

lab_server_ip() {
  printf '%s.2' "${MESH_SUBNET_PREFIX}"
}

lab_last_node_ip() {
  printf '%s.%s' "${MESH_SUBNET_PREFIX}" "${NODE_COUNT}"
}

resolve_mesh_network() {
  local node="${1:-${MESH_NODES[0]}}"
  local name

  if ! docker container inspect "${node}" >/dev/null 2>&1; then
    echo "ERROR: container '${node}' not found. Start the lab first: ./scripts/start_lab.sh" >&2
    return 1
  fi

  name="$(docker inspect "${node}" --format '{{range $n, $cfg := .NetworkSettings.Networks}}{{println $n}}{{end}}' \
    | grep -E '(^|_)manet$' | head -1)"

  if [[ -z "${name}" ]]; then
    echo "ERROR: could not resolve Docker network for '${node}' (expected *manet)." >&2
    return 1
  fi

  printf '%s' "${name}"
}

is_mesh_node() {
  local target="$1"
  local node
  for node in "${MESH_NODES[@]}"; do
    if [[ "${node}" == "${target}" ]]; then
      return 0
    fi
  done
  return 1
}
