#!/usr/bin/env bash
# Shared config, fault injection, and BATMAN/ELP metrics.

NODE_COUNT=30
MESH_SUBNET_PREFIX="10.0.0"
MESH_IFACE="eth0"
BATMAN_ETHERTYPE="0x4305"
LAB_CLIENT_NODE="node1"
LAB_SERVER_NODE="node2"

NODES=()
BAT_IPS=()
MESH_NODES=()
MESH_RANDOM_CANDIDATES=()
MESH_NETWORK=""

for i in $(seq 1 "${NODE_COUNT}"); do
  NODES+=("node${i}")
  BAT_IPS+=("${MESH_SUBNET_PREFIX}.${i}/24")
  MESH_NODES+=("node${i}")
done
for i in $(seq 3 "${NODE_COUNT}"); do
  MESH_RANDOM_CANDIDATES+=("node${i}")
done

lab_server_ip() { printf '%s.2' "${MESH_SUBNET_PREFIX}"; }
lab_last_node_ip() { printf '%s.%s' "${MESH_SUBNET_PREFIX}" "${NODE_COUNT}"; }

resolve_mesh_network() {
  local node="${1:-${MESH_NODES[0]}}"
  local name
  if ! docker container inspect "${node}" >/dev/null 2>&1; then
    echo "ERROR: container '${node}' not found. Run ./scripts/start_lab.sh" >&2
    return 1
  fi
  name="$(docker inspect "${node}" --format '{{range $n, $cfg := .NetworkSettings.Networks}}{{println $n}}{{end}}' \
    | grep -E '(^|_)manet$' | head -1)"
  [[ -n "${name}" ]] || { echo "ERROR: could not resolve manet network for ${node}" >&2; return 1; }
  printf '%s' "${name}"
}

is_mesh_node() {
  local target="$1" node
  for node in "${MESH_NODES[@]}"; do [[ "${node}" == "${target}" ]] && return 0; done
  return 1
}

require_docker() {
  command -v docker >/dev/null 2>&1 || { echo "ERROR: docker not found." >&2; exit 1; }
  docker info >/dev/null 2>&1 || { echo "ERROR: cannot connect to Docker daemon." >&2; exit 1; }
}

init_network() { MESH_NETWORK="$(resolve_mesh_network "${MESH_NODES[0]}")"; }

require_node() {
  local node="$1"
  is_mesh_node "${node}" || { echo "ERROR: invalid node '${node}'" >&2; exit 1; }
  docker container inspect "${node}" >/dev/null 2>&1 || { echo "ERROR: container '${node}' not found." >&2; exit 1; }
}

node_on_mesh_network() {
  docker inspect "$1" --format '{{range $n, $cfg := .NetworkSettings.Networks}}{{println $n}}{{end}}' \
    | grep -Fx "${MESH_NETWORK}" >/dev/null 2>&1
}

run_in_node() {
  local node="$1"; shift
  docker exec "${node}" bash -lc "$*"
}

restore_batman_hardif() {
  run_in_node "$1" "ip link set ${MESH_IFACE} up; batctl if add ${MESH_IFACE} 2>/dev/null || true"
}

mesh_disconnect() {
  local node="$1"
  require_node "${node}"
  node_on_mesh_network "${node}" || return 0
  echo "==> Disconnect ${node} from ${MESH_NETWORK}"
  docker network disconnect "${MESH_NETWORK}" "${node}"
}

mesh_reconnect() {
  local node="$1"
  require_node "${node}"
  if node_on_mesh_network "${node}"; then restore_batman_hardif "${node}"; return 0; fi
  echo "==> Reconnect ${node} to ${MESH_NETWORK}"
  docker network connect "${MESH_NETWORK}" "${node}"
  restore_batman_hardif "${node}"
}

mesh_reconnect_all() {
  local node
  for node in "${MESH_NODES[@]}"; do
    docker container inspect "${node}" >/dev/null 2>&1 && ! node_on_mesh_network "${node}" && mesh_reconnect "${node}"
  done
}

mesh_reset_netem_all() {
  local node
  for node in "${MESH_NODES[@]}"; do
    docker container inspect "${node}" >/dev/null 2>&1 && run_in_node "${node}" "tc qdisc del dev ${MESH_IFACE} root" || true
  done
}

mesh_reset_all() {
  mesh_reset_netem_all
  mesh_reconnect_all
}

set_mesh_density() {
  local density="$1" i node
  require_docker
  init_network
  echo "==> Mesh density: ${density} (node1..node${density})"
  for i in $(seq 1 "${NODE_COUNT}"); do
    node="node${i}"
    if [[ "${i}" -le "${density}" ]]; then mesh_reconnect "${node}" >/dev/null
    else mesh_disconnect "${node}" >/dev/null; fi
  done
}

pick_random_candidate() {
  printf '%s\n' "${MESH_RANDOM_CANDIDATES[@]}" | shuf | head -n 1
}

count_batman_traffic() {
  run_in_node "$1" "timeout $2 tcpdump -i ${MESH_IFACE} -nn -q ether proto ${BATMAN_ETHERTYPE} 2>/dev/null | wc -l | tr -d ' '"
}

batman_pps() {
  awk -v p="$1" -v s="$2" 'BEGIN { if (s>0) printf "%.2f", p/s; else print "0" }'
}

count_neighbors() {
  run_in_node "$1" "batctl n 2>/dev/null | grep -E '[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+' | wc -l | tr -d ' '" || echo "0"
}

count_originators() {
  run_in_node "$1" "batctl o 2>/dev/null | grep -E '[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+' | wc -l | tr -d ' '" || echo "0"
}

read_batman_sysfs() {
  run_in_node "$1" "cat /sys/class/net/bat0/mesh/$2 2>/dev/null" || echo "NA"
}

measure_ping() {
  run_in_node "$1" "ping -c ${3:-10} -i 0.2 -W 1 $2" 2>/dev/null || true
}

parse_ping_avg() { awk -F'/' '/rtt min\/avg\/max/ { print $5 }'; }
parse_ping_loss() { awk -F',' '/packet loss/ { gsub(/[^0-9.]/, "", $3); print $3 }'; }

measure_iperf() {
  run_in_node "$1" "iperf3 -c $2 -t ${3:-5} -f m" 2>/dev/null || true
}

parse_iperf_mbps() {
  awk '/sender$/ && /Mbits\/sec/ { for (i=1;i<=NF;i++) if ($i ~ /Mbits\/sec$/) { print $(i-1); exit } }'
}

collect_mesh_snapshot() {
  local client="$1" server_ip="$2" cap="$3" ping_n="$4" iperf_s="$5"
  local bp pps nbr orig pout pavg ploss iout thr

  bp="$(count_batman_traffic "${client}" "${cap}")"
  pps="$(batman_pps "${bp}" "${cap}")"
  nbr="$(count_neighbors "${client}")"
  orig="$(count_originators "${client}")"
  pout="$(measure_ping "${client}" "${server_ip}" "${ping_n}")"
  pavg="$(printf '%s\n' "${pout}" | parse_ping_avg)"; [[ -n "${pavg}" ]] || pavg="NA"
  ploss="$(printf '%s\n' "${pout}" | parse_ping_loss)"; [[ -n "${ploss}" ]] || ploss="NA"
  iout="$(measure_iperf "${client}" "${server_ip}" "${iperf_s}")"
  thr="$(printf '%s\n' "${iout}" | parse_iperf_mbps)"; [[ -n "${thr}" ]] || thr="NA"
  echo "${bp},${pps},${nbr},${orig},${pavg},${ploss},${thr}"
}

start_iperf_server() {
  run_in_node "${LAB_SERVER_NODE}" "pkill iperf3 >/dev/null 2>&1 || true; nohup iperf3 -s >/tmp/iperf3_server.log 2>&1 &"
}

stop_iperf_server() {
  run_in_node "${LAB_SERVER_NODE}" "pkill iperf3 >/dev/null 2>&1 || true" || true
}
