#!/usr/bin/env bash
# Shared config, fault injection, and BATMAN/ELP metrics.

NODE_COUNT=3
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
MANET_PARENT_IF="manet0"
MANET_UNDERLAY_SUBNET="172.30.255.0/24"

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
  run_in_node "$1" "
    sysctl -qw net.ipv4.conf.all.rp_filter=0 2>/dev/null || true
    sysctl -qw net.ipv4.conf.${MESH_IFACE}.rp_filter=0 2>/dev/null || true
    ip link set ${MESH_IFACE} up
    ip link set dev ${MESH_IFACE} promisc on 2>/dev/null || true
    ip -4 addr flush dev ${MESH_IFACE}
    if ip link show bat0 >/dev/null 2>&1; then
      batctl -m bat0 if add -M ${MESH_IFACE} 2>/dev/null || true
      batctl -m bat0 if en ${MESH_IFACE} 2>/dev/null || true
    fi
  "
}

ensure_manet_parent() {
  [[ "$(uname -s)" == "Linux" ]] || return 0
  if ! ip link show "${MANET_PARENT_IF}" >/dev/null 2>&1; then
    echo "==> Creating L2 parent ${MANET_PARENT_IF} (dummy) for macvlan MANET"
    sudo ip link add "${MANET_PARENT_IF}" type dummy
  fi
  sudo ip link set "${MANET_PARENT_IF}" up
}

ensure_host_batman_prereqs() {
  echo "==> Host tweaks for Docker + BATMAN"
  sudo modprobe batman-adv 2>/dev/null || true
  sudo sysctl -qw net.bridge.bridge-nf-call-iptables=0 2>/dev/null || true
  sudo sysctl -qw net.bridge.bridge-nf-call-ip6tables=0 2>/dev/null || true
  sudo sysctl -qw net.bridge.bridge-nf-call-arptables=0 2>/dev/null || true
  sudo sysctl -qw net.ipv4.conf.all.rp_filter=0 2>/dev/null || true
  sudo sysctl -qw net.ipv4.conf.default.rp_filter=0 2>/dev/null || true
}

tune_manet_bridge() {
  local net_id br_if driver
  init_network || return 0
  driver="$(docker network inspect "${MESH_NETWORK}" --format '{{.Driver}}' 2>/dev/null || true)"
  [[ "${driver}" == "bridge" ]] || return 0
  net_id="$(docker network inspect "${MESH_NETWORK}" --format '{{.Id}}' 2>/dev/null || true)"
  [[ -n "${net_id}" ]] || return 0
  br_if="br-${net_id:0:12}"
  if [[ ! -d "/sys/class/net/${br_if}/bridge" ]]; then
    echo "WARNING: bridge interface ${br_if} not found (network ${MESH_NETWORK})"
    return 0
  fi
  echo "==> Tuning Docker bridge ${br_if} for BATMAN L2 multicast"
  ensure_host_batman_prereqs || true
  echo 0 | sudo tee "/sys/class/net/${br_if}/bridge/multicast_snooping" >/dev/null 2>&1 || true
  echo 0 | sudo tee "/sys/class/net/${br_if}/bridge/multicast_querier" >/dev/null 2>&1 || true
  echo 65536 | sudo tee "/sys/class/net/${br_if}/bridge/ageing_time" >/dev/null 2>&1 || true
}

preflight_ubuntu_batman() {
  local ok=1
  echo "==> Ubuntu BATMAN preflight"
  if [[ "$(uname -s)" != "Linux" ]]; then
    echo "ERROR: BATMAN lab requires Linux (you are on $(uname -s))."
    return 1
  fi
  if ! command -v modprobe >/dev/null 2>&1; then
    echo "ERROR: install kmod: sudo apt install kmod"
    ok=0
  fi
  if ! modinfo batman-adv >/dev/null 2>&1; then
    echo "ERROR: batman-adv module missing."
    echo "       sudo apt install linux-modules-extra-\$(uname -r)"
    ok=0
  fi
  if ! lsmod | grep -q '^batman_adv'; then
    echo "==> Loading batman-adv on host"
    sudo modprobe batman-adv || ok=0
  fi
  ensure_manet_parent || ok=0
  ensure_host_batman_prereqs || true
  [[ "${ok}" -eq 1 ]]
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
  # batctl n lists MAC addresses, not IPs
  run_in_node "$1" "batctl -m bat0 n 2>/dev/null | grep -Ei '([0-9a-f]{2}:){5}[0-9a-f]{2}' | wc -l | tr -d ' '" || echo "0"
}

count_originators() {
  run_in_node "$1" "batctl -m bat0 o 2>/dev/null | grep -E '[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+' | wc -l | tr -d ' '" || echo "0"
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

# BATMAN-adv: attach eth0 to bat0 first, assign IP on bat0, then flush eth0.
configure_batman_node() {
  local node="$1"
  local bat_ip="$2"

  run_in_node "${node}" "
    set -e
    modprobe batman-adv 2>/dev/null || true
    sysctl -qw net.ipv4.conf.all.rp_filter=0
    sysctl -qw net.ipv4.conf.default.rp_filter=0
    sysctl -qw net.ipv4.conf.${MESH_IFACE}.rp_filter=0

    ip link set ${MESH_IFACE} up
    ip link set dev ${MESH_IFACE} promisc on

    ip link del bat0 2>/dev/null || true
    ip link add name bat0 type batadv

    batctl -m bat0 if del ${MESH_IFACE} 2>/dev/null || true
    batctl -m bat0 if add -M ${MESH_IFACE}
    batctl -m bat0 if en ${MESH_IFACE}

    ip link set bat0 up
    echo 0 > /sys/class/net/bat0/mesh/bridge_loop_avoidance 2>/dev/null || true
    echo 0 > /sys/class/net/bat0/mesh/ap_isolation 2>/dev/null || true

    ip -4 addr flush dev bat0
    ip addr add ${bat_ip} dev bat0

    ip -4 addr flush dev ${MESH_IFACE}
    ip -6 addr flush dev ${MESH_IFACE} 2>/dev/null || true

    batctl -m bat0 if | grep -q ${MESH_IFACE}
  "
}

reconcile_batman_hardifs() {
  local node
  for node in "${NODES[@]}"; do
    restore_batman_hardif "${node}" >/dev/null 2>&1 || true
  done
}

mesh_ping_test() {
  local client="$1"
  local target_ip="$2"
  run_in_node "${client}" "batctl -m bat0 ping -c 3 ${target_ip}" 2>/dev/null \
    || run_in_node "${client}" "ping -c 3 -W 2 ${target_ip}" 2>/dev/null
}

wait_for_mesh_convergence() {
  local observer="${1:-${LAB_CLIENT_NODE}}"
  local want="${2:-$((NODE_COUNT - 1))}"
  local timeout="${3:-90}"
  local elapsed=0 n o

  echo "==> Waiting for BATMAN mesh (expect >= ${want} neighbors on ${observer})"
  while [[ "${elapsed}" -lt "${timeout}" ]]; do
    n="$(count_neighbors "${observer}")"
    o="$(count_originators "${observer}")"
    if [[ "${n}" -ge "${want}" || "${o}" -ge $((want + 1)) ]]; then
      echo "    Mesh ready: neighbors=${n} originators=${o} (${elapsed}s)"
      return 0
    fi
    if (( elapsed > 0 && elapsed % 10 == 0 )); then
      reconcile_batman_hardifs
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done

  reconcile_batman_hardifs
  sleep 3
  n="$(count_neighbors "${observer}")"
  o="$(count_originators "${observer}")"
  if [[ "${n}" -ge "${want}" || "${o}" -ge $((want + 1)) ]]; then
    echo "    Mesh ready after reconcile: neighbors=${n} originators=${o}"
    return 0
  fi
  echo "WARNING: mesh not converged after ${timeout}s (neighbors=${n}, originators=${o}, want>=${want})"
  show_mesh_diagnostics "${observer}"
  return 1
}

show_mesh_diagnostics() {
  local node="${1:-${LAB_CLIENT_NODE}}"
  echo "==> Diagnostics on ${node}"
  run_in_node "${node}" "
    echo '--- batctl if ---'
    batctl -m bat0 if 2>/dev/null || batctl if 2>/dev/null || true
    echo '--- ip link master bat0 ---'
    ip link show master bat0 2>/dev/null || echo 'no slaves on bat0'
    echo '--- batctl n ---'
    batctl -m bat0 n 2>/dev/null || true
    echo '--- batctl o ---'
    batctl -m bat0 o 2>/dev/null || true
    echo '--- ip addr ---'
    ip -4 addr show dev ${MESH_IFACE}
    ip -4 addr show dev bat0
    echo '--- promisc ---'
    ip link show dev ${MESH_IFACE} | grep -i promisc || true
  "
}
