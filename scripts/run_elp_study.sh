#!/usr/bin/env bash
set -euo pipefail

# Fully automated ELP study: density benchmark + random walk + analysis.
#
# Usage:
#   ./scripts/run_elp_study.sh [random_walk_steps]

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

RW_STEPS="${1:-20}"

echo "==> [1/5] Starting virtual test environment"
"${ROOT}/scripts/start_lab.sh"

echo ""
echo "==> [2/5] Density benchmark (5..30 nodes, ELP/BATMAN traffic)"
"${ROOT}/scripts/elp_density_benchmark.sh" "5 10 15 20 25 30" 30 45

echo ""
echo "==> [3/5] Random-walk churn + ELP analysis (${RW_STEPS} steps)"
"${ROOT}/scripts/mesh_random_walk.sh" "${RW_STEPS}" 10 10 5

echo ""
echo "==> [4/5] Global analysis"
"${ROOT}/scripts/analyze_study.sh"

echo ""
echo "==> [5/5] Study complete"
echo ""
echo "Observe BATMAN live during tests:"
echo "  ./scripts/observe_batman.sh node1 watch"
echo "  ./scripts/observe_batman.sh node1 traffic 30"
echo ""
echo "Report guide: docs/TRAVAIL.md"
