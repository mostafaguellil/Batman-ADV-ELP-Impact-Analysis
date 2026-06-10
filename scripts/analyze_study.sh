#!/usr/bin/env bash
set -euo pipefail

# Summarize latest density + random-walk results.
#
# Usage:
#   ./scripts/analyze_study.sh

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RESULTS="${ROOT}/results"

density_csv="$(ls -t "${RESULTS}"/elp_density_*.csv 2>/dev/null | head -1 || true)"
walk_csv="$(ls -t "${RESULTS}"/mesh_random_walk_*.csv 2>/dev/null | head -1 || true)"

echo "===== Full Study Analysis ====="
echo ""

if [[ -n "${density_csv}" ]]; then
  echo ">> Density benchmark"
  "${ROOT}/scripts/summarize_elp_benchmark.sh" "${density_csv}"
  echo ""
else
  echo "No elp_density_*.csv found. Run: ./scripts/elp_density_benchmark.sh"
  echo ""
fi

if [[ -n "${walk_csv}" ]]; then
  echo ">> Random walk churn"
  "${ROOT}/scripts/summarize_random_walk.sh" "${walk_csv}"
  echo ""
else
  echo "No mesh_random_walk_*.csv found. Run: ./scripts/mesh_random_walk.sh"
  echo ""
fi

if [[ -n "${density_csv}" && -n "${walk_csv}" ]]; then
  echo "----- Files for report -----"
  echo "  ${density_csv}"
  echo "  ${walk_csv}"
fi
