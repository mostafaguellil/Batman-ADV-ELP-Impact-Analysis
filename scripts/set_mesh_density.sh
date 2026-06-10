#!/usr/bin/env bash
set -euo pipefail

# Connect node1..nodeN on the manet bridge; disconnect the rest.
#
# Usage: ./scripts/set_mesh_density.sh <density>

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lab_config.sh
source "${ROOT}/scripts/lab_config.sh"
# shellcheck source=scripts/mesh_fault_lib.sh
source "${ROOT}/scripts/mesh_fault_lib.sh"

DENSITY="${1:-}"

if [[ -z "${DENSITY}" || "${DENSITY}" == "-h" || "${DENSITY}" == "--help" ]]; then
  echo "Usage: $0 <density>   # active nodes: node1 .. node<density> (max ${NODE_COUNT})"
  exit 0
fi

if ! [[ "${DENSITY}" =~ ^[0-9]+$ ]] || [[ "${DENSITY}" -lt 1 ]] || [[ "${DENSITY}" -gt "${NODE_COUNT}" ]]; then
  echo "ERROR: density must be between 1 and ${NODE_COUNT}" >&2
  exit 1
fi

require_docker
init_network

echo "==> Setting mesh density to ${DENSITY} (active: node1..node${DENSITY})"

for i in $(seq 1 "${NODE_COUNT}"); do
  node="node${i}"
  if [[ "${i}" -le "${DENSITY}" ]]; then
    mesh_reconnect "${node}" >/dev/null
  else
    mesh_disconnect "${node}" >/dev/null
  fi
done

echo "==> Density ${DENSITY} applied"
