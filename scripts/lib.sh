#!/usr/bin/env bash
# Shared config, fault injection, and BATMAN/ELP metrics.

NODE_COUNT=30
MESH_PARALLEL_JOBS=10
MESH_SUBNET_PREFIX="10.0.0"
MESH_IFACE="eth0"
BATMAN_ETHERTYPE="0x4305"
BATMESH_IF="bat0"
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

mesh_convergence_timeout() {
  local want="${1:-$((NODE_COUNT - 1))}"
  local t=$((60 + want * 5))
  (( t > 300 )) && t=300
  printf '%s' "${t}"
}

mesh_neighbors_want() {
  local density="${1:-${NODE_COUNT}}"
  echo $((density - 1))
}

run_nodes_parallel() {
  local batch="${MESH_PARALLEL_JOBS}" i j pid pids=() rc=0
  for ((i = 0; i < ${#NODES[@]}; i += batch)); do
    pids=()
    for ((j = i; j < i + batch && j < ${#NODES[@]}; j++)); do
      "$@" "${NODES[$j]}" &
      pids+=($!)
    done
    for pid in "${pids[@]}"; do
      wait "${pid}" || rc=1
    done
  done
  return "${rc}"
}

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
      ip link set dev ${MESH_IFACE} master bat0 2>/dev/null || \
        batctl meshif bat0 interface add -M ${MESH_IFACE} 2>/dev/null || true
      ip link set ${MESH_IFACE} up
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

ensure_container_tools() {
  local node missing=()
  for node in "${NODES[@]}"; do
    for cmd in batctl ip iperf3 tcpdump ping; do
      if ! docker exec "${node}" bash -lc "command -v ${cmd}" >/dev/null 2>&1; then
        missing+=("${node}:${cmd}")
      fi
    done
  done
  if ((${#missing[@]} > 0)); then
    echo "ERROR: missing tools in containers: ${missing[*]}"
    echo "Hint: docker compose build && docker compose up -d --force-recreate"
    return 1
  fi
  echo "==> Container tools OK (batctl, iproute2, iperf3, tcpdump, ping)"
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
    docker container inspect "${node}" >/dev/null 2>&1 \
      && run_in_node "${node}" "tc qdisc show dev ${MESH_IFACE} 2>/dev/null | grep -q netem && tc qdisc del dev ${MESH_IFACE} root 2>/dev/null" \
      || true
  done
}

mesh_reset_all() {
  mesh_reset_netem_all
  mesh_reconnect_all
}

set_mesh_density() {
  local density="$1" i node pids=()
  require_docker
  init_network
  echo "==> Mesh density: ${density} (node1..node${density})"
  for i in $(seq 1 "${NODE_COUNT}"); do
    node="node${i}"
    if [[ "${i}" -le "${density}" ]]; then
      mesh_reconnect "${node}" >/dev/null &
      pids+=($!)
    else
      mesh_disconnect "${node}" >/dev/null &
      pids+=($!)
    fi
  done
  for pid in "${pids[@]}"; do wait "${pid}" 2>/dev/null || true; done
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
  # One row per direct neighbor (MAC + last-seen), not every MAC on the line
  run_in_node "$1" "batctl meshif ${BATMESH_IF} n 2>/dev/null \
    | grep -E '^[[:space:]]*[^[:space:]]+[[:space:]]+([0-9a-f]{2}:){5}[0-9a-f]{2}' \
    | wc -l | tr -d ' '" || echo "0"
}

count_originators() {
  # batctl o lists originator MACs (not 10.0.0.x IPs)
  run_in_node "$1" "batctl meshif ${BATMESH_IF} o 2>/dev/null \
    | grep -E '^[[:space:]]*([0-9a-f]{2}:){5}[0-9a-f]{2}' \
    | wc -l | tr -d ' '" || echo "0"
}

read_batman_sysfs() {
  run_in_node "$1" "cat /sys/class/net/bat0/mesh/$2 2>/dev/null" || echo "NA"
}

measure_ping() {
  run_in_node "$1" "batctl meshif ${BATMESH_IF} ping -c ${3:-10} -t 2 $2" 2>/dev/null \
    || run_in_node "$1" "ping -c ${3:-10} -i 0.2 -W 2 $2" 2>/dev/null \
    || true
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

# BATMAN-adv: kernel attaches eth0 under bat0; IP only on bat0.
configure_batman_node() {
  local node="$1"
  local bat_ip="$2"

  run_in_node "${node}" "
    set -e
    modprobe batman-adv 2>/dev/null || true
    for dev in all default ${MESH_IFACE} bat0; do
      sysctl -qw net.ipv4.conf.\${dev}.rp_filter=0 2>/dev/null || true
    done

    ip link set ${MESH_IFACE} up
    ip link set dev ${MESH_IFACE} promisc on

    ip link del bat0 2>/dev/null || true
    ip link add name bat0 type batadv
    ip link set dev bat0 mtu 1500 2>/dev/null || true

    batctl meshif bat0 interface del ${MESH_IFACE} 2>/dev/null || true
    if ! ip link set dev ${MESH_IFACE} master bat0 2>/dev/null; then
      batctl meshif bat0 interface add -M ${MESH_IFACE}
    fi
    ip link set dev ${MESH_IFACE} up
    ip link set dev bat0 up

    batctl meshif bat0 bridge_loop_avoidance 0 2>/dev/null || true
    batctl meshif bat0 ap_isolation 0 2>/dev/null || true
    batctl meshif bat0 distributed_arp_table enable 2>/dev/null || true
    for _k in bridge_loop_avoidance ap_isolation; do
      _p=/sys/class/net/bat0/mesh/\${_k}
      [[ -w \${_p} ]] && echo 0 > \${_p}
    done
    _d=/sys/class/net/bat0/mesh/distributed_arp_table
    [[ -w \${_d} ]] && echo 1 > \${_d}

    ip -4 addr flush dev bat0
    ip addr add ${bat_ip} dev bat0

    ip -4 addr flush dev ${MESH_IFACE}
    ip -6 addr flush dev ${MESH_IFACE} 2>/dev/null || true

    ip link show master bat0 | grep -q ${MESH_IFACE}
  "
}

_finalize_batman_node() {
  run_in_node "$1" "
    sysctl -qw net.ipv4.conf.bat0.rp_filter=0 2>/dev/null || true
    batctl meshif bat0 distributed_arp_table enable 2>/dev/null || true
    _d=/sys/class/net/bat0/mesh/distributed_arp_table
    [[ -w \${_d} ]] && echo 1 > \${_d}
    ip link set bat0 up 2>/dev/null || true
    ip neigh flush dev bat0 2>/dev/null || true
  " 2>/dev/null || true
}

configure_all_batman_nodes() {
  local i j node bat_ip pids=() batch="${MESH_PARALLEL_JOBS}"
  echo "==> Configuring BATMAN on ${NODE_COUNT} nodes (parallel x${batch})"
  for ((i = 0; i < ${#NODES[@]}; i += batch)); do
    pids=()
    for ((j = i; j < i + batch && j < ${#NODES[@]}; j++)); do
      node="${NODES[$j]}"
      bat_ip="${BAT_IPS[$j]}"
      configure_batman_node "${node}" "${bat_ip}" &
      pids+=($!)
    done
    for pid in "${pids[@]}"; do wait "${pid}" || return 1; done
  done
}

finalize_batman_mesh() {
  local quiet="${1:-0}"
  [[ "${quiet}" -eq 1 ]] || echo "==> Finalizing BATMAN data plane on all nodes"
  run_nodes_parallel _finalize_batman_node || true
  [[ "${quiet}" -eq 1 ]] || sleep 3
}

mesh_has_route() {
  local observer="$1"
  local target_ip="$2"
  run_in_node "${observer}" "batctl meshif ${BATMESH_IF} o 2>/dev/null | grep -qw '${target_ip}'"
}

mesh_routes_ready() {
  local observer="${1:-${LAB_CLIENT_NODE}}"
  mesh_has_route "${observer}" "$(lab_server_ip)" \
    && mesh_has_route "${observer}" "$(lab_last_node_ip)"
}

reconcile_batman_hardifs() {
  local i j pids=() batch="${MESH_PARALLEL_JOBS}"
  for ((i = 0; i < ${#NODES[@]}; i += batch)); do
    pids=()
    for ((j = i; j < i + batch && j < ${#NODES[@]}; j++)); do
      restore_batman_hardif "${NODES[$j]}" &
      pids+=($!)
    done
    for pid in "${pids[@]}"; do wait "${pid}" 2>/dev/null || true; done
  done
}

mesh_ping_test() {
  local client="$1"
  local target_ip="$2"
  local tries="${3:-15}"
  local i

  for ((i = 1; i <= tries; i++)); do
    if run_in_node "${client}" "batctl meshif ${BATMESH_IF} ping -c 1 -t 5 ${target_ip}" 2>/dev/null; then
      return 0
    fi
    if run_in_node "${client}" "ping -c 1 -W 5 ${target_ip}" 2>/dev/null; then
      return 0
    fi
    sleep 2
  done
  return 1
}

prove_mesh_connectivity() {
  local client="$1"
  local target_ip="$2"
  local attempt max=25

  echo "==> Proving mesh connectivity ${client} -> ${target_ip}"
  for ((attempt = 1; attempt <= max; attempt++)); do
    if mesh_ping_test "${client}" "${target_ip}" 1; then
      echo "    batctl ping OK (attempt ${attempt})"
      run_in_node "${client}" "batctl meshif ${BATMESH_IF} ping -c 3 -t 5 ${target_ip}" 2>/dev/null || true
      run_in_node "${client}" "ping -c 3 -W 5 ${target_ip}" 2>/dev/null || true
      return 0
    fi
    if (( attempt % 5 == 0 )); then
      finalize_batman_mesh 1
      reconcile_batman_hardifs
    fi
    sleep 2
  done
  return 1
}

wait_for_mesh_convergence() {
  local observer="${1:-${LAB_CLIENT_NODE}}"
  local want="${2:-$((NODE_COUNT - 1))}"
  local timeout="${3:-$(mesh_convergence_timeout "${want}")}"
  local min_ok=$(( want * 85 / 100 ))
  (( min_ok < 1 )) && min_ok=1
  local elapsed=0 n

  echo "==> Waiting for BATMAN neighbors on ${observer} (want >= ${want}, ok >= ${min_ok}, timeout ${timeout}s)"
  while [[ "${elapsed}" -lt "${timeout}" ]]; do
    n="$(count_neighbors "${observer}")"
    if [[ "${n}" -ge "${want}" || ( "${want}" -ge 5 && "${n}" -ge "${min_ok}" ) ]]; then
      echo "    Neighbors ready: ${n}/${want} (${elapsed}s)"
      return 0
    fi
    if (( elapsed > 0 && elapsed % 15 == 0 )); then
      finalize_batman_mesh 1
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done

  n="$(count_neighbors "${observer}")"
  if [[ "${n}" -ge "${min_ok}" ]]; then
    echo "    Neighbors partial: ${n}/${want} (${elapsed}s)"
    return 0
  fi
  echo "WARNING: only ${n}/${want} neighbors after ${timeout}s"
  show_mesh_diagnostics "${observer}"
  return 1
}

show_mesh_diagnostics() {
  local node="${1:-${LAB_CLIENT_NODE}}"
  echo "==> Diagnostics on ${node}"
  run_in_node "${node}" "
    echo '--- batctl interface ---'
    batctl meshif bat0 interface 2>/dev/null || true
    echo '--- ip link master bat0 ---'
    ip link show master bat0 2>/dev/null || echo 'no slaves on bat0'
    echo '--- batctl n ---'
    batctl meshif bat0 n 2>/dev/null || true
    echo '--- batctl o ---'
    batctl meshif bat0 o 2>/dev/null || true
    echo '--- ip addr ---'
    ip -4 addr show dev ${MESH_IFACE}
    ip -4 addr show dev bat0
    echo '--- batctl ping ---'
    batctl meshif bat0 ping -c 1 -t 2 $(lab_server_ip) 2>&1 || true
    echo '--- ip neigh bat0 ---'
    ip neigh show dev bat0 2>/dev/null || true
  "
}
