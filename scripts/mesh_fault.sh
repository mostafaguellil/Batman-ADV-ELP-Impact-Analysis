#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/mesh_fault_lib.sh
source "${ROOT}/scripts/mesh_fault_lib.sh"

usage() {
  cat <<'EOF'
BATMAN-adv mesh fault injection (Solution 1 + Solution 2)

Solution 1 — hard disconnect/reconnect (Docker L2):
  disconnect <node>              Remove node from the manet bridge (full link loss)
  reconnect <node>               Re-attach node to manet and restore eth0/bat0

Solution 2 — link degradation (tc netem on eth0):
  degrade <node> <loss%> <delay_ms> [jitter_ms]
                                 Apply packet loss + delay on the underlay interface
  reset <node>                   Remove netem qdisc (ignores missing qdisc)
  reset-all                      Reset netem on all nodes; reconnect any disconnected nodes

Optional automation:
  random [rounds] [interval_sec] [candidate_count]
                                 Randomly disconnect or degrade candidate nodes (node3..node30)
  random-walk [steps] [down_secs] [up_secs] [capture_secs]
                                 One node at a time + automated ELP/BATMAN CSV analysis

Examples:
  ./scripts/mesh_fault.sh disconnect node3
  ./scripts/mesh_fault.sh reconnect node3
  ./scripts/mesh_fault.sh degrade node5 15 80 20
  ./scripts/mesh_fault.sh reset node5
  ./scripts/mesh_fault.sh reset-all
  ./scripts/mesh_fault.sh random 10 15 2
  ./scripts/mesh_fault.sh random-walk 20 10 10 5

Notes:
  - Faults apply to eth0, the BATMAN-adv hard interface (Layer 2 underlay).
  - disconnect uses: docker network disconnect/connect <network> <node>
  - degrade uses:     docker exec <node> tc qdisc replace dev eth0 root netem ...
EOF
}

cmd_disconnect() {
  mesh_disconnect "$@"
}

cmd_reconnect() {
  mesh_reconnect "$@"
}

cmd_degrade() {
  local node="$1"
  local loss="$2"
  local delay_ms="$3"
  local jitter_ms="${4:-0}"

  require_node "${node}"

  if ! node_on_mesh_network "${node}"; then
    echo "ERROR: ${node} is disconnected from ${MESH_NETWORK}. Reconnect first." >&2
    exit 1
  fi

  echo "==> Degrading ${node} on ${MESH_IFACE}: loss=${loss}% delay=${delay_ms}ms jitter=${jitter_ms}ms"
  run_in_node "${node}" \
    "tc qdisc replace dev ${MESH_IFACE} root netem loss ${loss}% delay ${delay_ms}ms ${jitter_ms}ms"
  echo "    netem affects all egress on ${MESH_IFACE}, including BATMAN OGM/ELP frames."
}

cmd_reset() {
  local node="$1"
  require_node "${node}"

  echo "==> Resetting netem on ${node}:${MESH_IFACE}"
  run_in_node "${node}" "tc qdisc del dev ${MESH_IFACE} root" || true
}

cmd_reset_all() {
  mesh_reset_all
}

cmd_random() {
  local rounds="${1:-5}"
  local interval_sec="${2:-10}"
  local candidate_count="${3:-1}"
  local round node loss delay jitter

  if [[ "${candidate_count}" -lt 1 ]]; then
    echo "ERROR: candidate_count must be >= 1" >&2
    exit 1
  fi
  if [[ "${candidate_count}" -gt "${#MESH_RANDOM_CANDIDATES[@]}" ]]; then
    echo "ERROR: candidate_count must be <= ${#MESH_RANDOM_CANDIDATES[@]}" >&2
    exit 1
  fi

  echo "==> Random fault mode: rounds=${rounds} interval=${interval_sec}s candidates=${candidate_count}"
  trap 'cmd_reset_all' EXIT

  for round in $(seq 1 "${rounds}"); do
    echo ""
    echo "--- Round ${round}/${rounds} ---"
    cmd_reset_all

    selected=()
    while IFS= read -r node; do
      [[ -n "${node}" ]] && selected+=("${node}")
    done < <(pick_random_candidates "${candidate_count}")
    for node in "${selected[@]}"; do
      if (( RANDOM % 2 == 0 )); then
        echo "Random: disconnect ${node}"
        cmd_disconnect "${node}"
      else
        loss=$((RANDOM % 31 + 5))     # 5-35%
        delay=$((RANDOM % 151 + 20))  # 20-170 ms
        jitter=$((RANDOM % 41))      # 0-40 ms
        echo "Random: degrade ${node} (loss=${loss}% delay=${delay}ms jitter=${jitter}ms)"
        cmd_degrade "${node}" "${loss}" "${delay}" "${jitter}"
      fi
    done

    sleep "${interval_sec}"
  done

  trap - EXIT
  cmd_reset_all
  echo "==> Random fault mode complete (all nodes reset/reconnected)"
}

cmd_random_walk() {
  exec "${ROOT}/scripts/mesh_random_walk.sh" "$@"
}

main() {
  local cmd="${1:-}"

  if [[ -z "${cmd}" || "${cmd}" == "-h" || "${cmd}" == "--help" ]]; then
    usage
    exit 0
  fi

  require_docker
  init_network

  case "${cmd}" in
    disconnect)
      [[ $# -ge 2 ]] || { echo "Usage: $0 disconnect <node>" >&2; exit 1; }
      cmd_disconnect "$2"
      ;;
    reconnect)
      [[ $# -ge 2 ]] || { echo "Usage: $0 reconnect <node>" >&2; exit 1; }
      cmd_reconnect "$2"
      ;;
    degrade)
      [[ $# -ge 4 ]] || { echo "Usage: $0 degrade <node> <loss%> <delay_ms> [jitter_ms]" >&2; exit 1; }
      cmd_degrade "$2" "$3" "$4" "${5:-0}"
      ;;
    reset)
      [[ $# -ge 2 ]] || { echo "Usage: $0 reset <node>" >&2; exit 1; }
      cmd_reset "$2"
      ;;
    reset-all)
      cmd_reset_all
      ;;
    random)
      cmd_random "${2:-5}" "${3:-10}" "${4:-1}"
      ;;
    random-walk)
      shift
      cmd_random_walk "$@"
      ;;
    *)
      echo "ERROR: unknown command '${cmd}'" >&2
      usage
      exit 1
      ;;
  esac
}

main "$@"
