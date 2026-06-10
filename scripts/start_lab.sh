#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"
# shellcheck source=scripts/lib.sh
source "${ROOT}/scripts/lib.sh"

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker not found."
  exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "ERROR: docker compose plugin not found."
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "ERROR: Cannot connect to Docker daemon. Start Docker Engine, then retry."
  exit 1
fi

if [[ "$(uname -s)" == "Linux" ]]; then
  preflight_ubuntu_batman
fi

echo "==> Starting MANET nodes (${NODE_COUNT} containers on macvlan/${MANET_PARENT_IF})…"
docker compose up -d

echo "==> Configuring BATMAN-Adv mesh…"
if [[ "$(uname -s)" == "Linux" ]]; then
  tune_manet_bridge || true
fi

"${ROOT}/scripts/setup_batman.sh" batman --skip-compose

echo "==> Starting iperf3 server on node2 (port 5201)…"
if docker exec node2 bash -lc "ss -ltn 2>/dev/null | grep -q ':5201 '"; then
  echo "    (iperf3 already listening on 5201)"
else
  docker exec -d node2 bash -lc "iperf3 -s"
fi

echo ""
echo "Lab is ready — real BATMAN mesh on ${MESH_SUBNET_PREFIX}.0/24"
echo ""
echo "Verify:"
echo "  docker exec node1 bash -lc \"batctl -m bat0 n\""
echo "  docker exec node1 bash -lc \"ping -c 3 10.0.0.2\""
echo "  ./scripts/observe_batman.sh node1 all"
