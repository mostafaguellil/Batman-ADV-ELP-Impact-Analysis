#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib.sh
source "${ROOT}/scripts/lib.sh"

usage() {
  cat <<'EOF'
Mesh fault injection

  disconnect <node>     docker network disconnect (full L2 loss)
  reconnect <node>      docker network connect + restore bat0
  degrade <node> <loss%> <delay_ms> [jitter_ms]   tc netem on eth0
  reset <node>          remove netem qdisc
  reset-all             reset netem + reconnect all nodes
EOF
}

main() {
  local cmd="${1:-}"
  [[ -z "${cmd}" || "${cmd}" == "-h" || "${cmd}" == "--help" ]] && { usage; exit 0; }

  require_docker
  init_network

  case "${cmd}" in
    disconnect)
      [[ $# -ge 2 ]] || { echo "Usage: $0 disconnect <node>" >&2; exit 1; }
      require_node "$2"; mesh_disconnect "$2" ;;
    reconnect)
      [[ $# -ge 2 ]] || { echo "Usage: $0 reconnect <node>" >&2; exit 1; }
      require_node "$2"; mesh_reconnect "$2" ;;
    degrade)
      [[ $# -ge 4 ]] || { echo "Usage: $0 degrade <node> <loss%> <delay_ms> [jitter]" >&2; exit 1; }
      require_node "$2"
      node_on_mesh_network "$2" || { echo "ERROR: $2 disconnected" >&2; exit 1; }
      run_in_node "$2" "tc qdisc replace dev ${MESH_IFACE} root netem loss $3% delay ${4}ms ${5:-0}ms"
      ;;
    reset)
      [[ $# -ge 2 ]] || { echo "Usage: $0 reset <node>" >&2; exit 1; }
      require_node "$2"
      run_in_node "$2" "tc qdisc del dev ${MESH_IFACE} root" || true
      ;;
    reset-all) mesh_reset_all ;;
    *) echo "ERROR: unknown command '${cmd}'" >&2; usage; exit 1 ;;
  esac
}

main "$@"
