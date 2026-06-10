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
  echo "ERROR: Cannot connect to Docker daemon. Start Docker Desktop/Engine, then retry."
  exit 1
fi

echo "==> Starting MANET nodes (${NODE_COUNT} containers)…"
docker compose up -d

echo "==> Configuring MANET (BATMAN first, fallback if mesh fails)…"
if [[ "$(uname -s)" == "Linux" ]]; then
  ensure_host_batman_prereqs || true
  tune_manet_bridge || true
fi

if ! "${ROOT}/scripts/setup_batman.sh" batman --skip-compose; then
  echo ""
  echo "WARNING: BATMAN setup failed — switching to fallback mode (IPs on eth0)."
  echo "         Real BATMAN/ELP metrics will NOT be available."
  echo "         Run ./scripts/debug_mesh.sh to troubleshoot."
  "${ROOT}/scripts/setup_batman.sh" fallback --skip-compose
fi

echo "==> Starting iperf3 server on node2 (port 5201)…"
if docker exec node2 bash -lc "ss -ltn 2>/dev/null | grep -q ':5201 '"; then
  echo "    (iperf3 already listening on 5201)"
else
  docker exec -d node2 bash -lc "iperf3 -s"
fi

echo ""
echo "Lab is ready (${NODE_COUNT} MANET nodes on ${MESH_SUBNET_PREFIX}.0/24)."
echo ""
echo "Quick checks:"
echo "  docker exec node1 bash -lc \"ping -c 3 10.0.0.2\""
echo "  ./scripts/observe_batman.sh node1 all"
echo "  ./scripts/debug_mesh.sh"
