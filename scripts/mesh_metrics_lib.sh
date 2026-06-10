#!/usr/bin/env bash
# Shared BATMAN/ELP measurement helpers.

BATMAN_ETHERTYPE="0x4305"

count_batman_traffic() {
  local node="$1"
  local duration="$2"
  run_in_node "${node}" "
    timeout ${duration} tcpdump -i ${MESH_IFACE} -nn -q ether proto ${BATMAN_ETHERTYPE} 2>/dev/null \
      | wc -l | tr -d ' '
  "
}

batman_pps() {
  local packets="$1"
  local duration="$2"
  awk -v p="${packets}" -v s="${duration}" 'BEGIN { if (s>0) printf "%.2f", p/s; else print "0" }'
}

count_neighbors() {
  local node="$1"
  run_in_node "${node}" \
    "batctl n 2>/dev/null | grep -E '[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+' | wc -l | tr -d ' '" || echo "0"
}

count_originators() {
  local node="$1"
  run_in_node "${node}" \
    "batctl o 2>/dev/null | grep -E '[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+' | wc -l | tr -d ' '" || echo "0"
}

read_batman_sysfs() {
  local node="$1"
  local key="$2"
  run_in_node "${node}" "cat /sys/class/net/bat0/mesh/${key} 2>/dev/null" || echo "NA"
}

measure_ping() {
  local client="$1"
  local target_ip="$2"
  local count="${3:-10}"
  run_in_node "${client}" "ping -c ${count} -i 0.2 -W 1 ${target_ip}" 2>/dev/null || true
}

parse_ping_avg() {
  awk -F'/' '/rtt min\/avg\/max/ { print $5 }'
}

parse_ping_loss() {
  awk -F',' '/packet loss/ { gsub(/[^0-9.]/, "", $3); print $3 }'
}

measure_iperf() {
  local client="$1"
  local target_ip="$2"
  local seconds="${3:-5}"
  run_in_node "${client}" "iperf3 -c ${target_ip} -t ${seconds} -f m" 2>/dev/null || true
}

parse_iperf_mbps() {
  awk '/sender$/ && /Mbits\/sec/ {
    for (i=1; i<=NF; i++) if ($i ~ /Mbits\/sec$/) { print $(i-1); exit }
  }'
}

# Collect one snapshot; prints CSV line (no header).
collect_mesh_snapshot() {
  local client="$1"
  local server_ip="$2"
  local capture_secs="$3"
  local ping_count="$4"
  local iperf_secs="$5"

  local batman_packets batman_pps neighbors originators ping_out ping_avg ping_loss
  local iperf_out throughput

  batman_packets="$(count_batman_traffic "${client}" "${capture_secs}")"
  batman_pps="$(batman_pps "${batman_packets}" "${capture_secs}")"
  neighbors="$(count_neighbors "${client}")"
  originators="$(count_originators "${client}")"

  ping_out="$(measure_ping "${client}" "${server_ip}" "${ping_count}")"
  ping_avg="$(printf '%s\n' "${ping_out}" | parse_ping_avg)"
  ping_loss="$(printf '%s\n' "${ping_out}" | parse_ping_loss)"
  [[ -n "${ping_avg}" ]] || ping_avg="NA"
  [[ -n "${ping_loss}" ]] || ping_loss="NA"

  iperf_out="$(measure_iperf "${client}" "${server_ip}" "${iperf_secs}")"
  throughput="$(printf '%s\n' "${iperf_out}" | parse_iperf_mbps)"
  [[ -n "${throughput}" ]] || throughput="NA"

  echo "${batman_packets},${batman_pps},${neighbors},${originators},${ping_avg},${ping_loss},${throughput}"
}
