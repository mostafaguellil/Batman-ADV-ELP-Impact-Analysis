#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib.sh
source "${ROOT}/scripts/lib.sh"

require_docker

fail=0
n="$(count_neighbors "${LAB_CLIENT_NODE}")"
want=$((NODE_COUNT - 1))
min=$(( want * 85 / 100 )); (( min < 1 )) && min=1
[[ "${n}" -ge "${min}" ]] || { echo "FAIL: neighbors=${n} (want >= ${min}, full mesh ${want})"; fail=1; }

if ! mesh_ping_test "${LAB_CLIENT_NODE}" "$(lab_server_ip)" 5; then
  echo "FAIL: ping $(lab_server_ip) from ${LAB_CLIENT_NODE}"
  fail=1
else
  echo "OK: ping $(lab_server_ip)"
fi

if [[ "${fail}" -eq 0 ]]; then
  echo "OK: BATMAN mesh verified"
  exit 0
fi
show_mesh_diagnostics "${LAB_CLIENT_NODE}"
exit 1
