#!/usr/bin/env bash
set -euo pipefail

# Full automated study: setup + density + random walk + analysis.
# Usage: ./scripts/run_study.sh [random_walk_steps]

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STEPS="${1:-20}"

"${ROOT}/scripts/start_lab.sh"
"${ROOT}/scripts/density_benchmark.sh" "5 10 15 20 25 30" 30 45
"${ROOT}/scripts/random_walk.sh" "${STEPS}" 10 10 5
"${ROOT}/scripts/summarize_results.sh"

echo ""
echo "Observe BATMAN: ./scripts/observe_batman.sh node1 watch"
echo "Report: docs/TRAVAIL.md"
