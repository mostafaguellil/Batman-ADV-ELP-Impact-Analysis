#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./scripts/summarize_elp_benchmark.sh <results/elp_density_*.csv>

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <elp_density.csv>"
  exit 1
fi

CSV="$1"
if [[ ! -f "${CSV}" ]]; then
  echo "ERROR: file not found: ${CSV}" >&2
  exit 1
fi

echo "===== ELP Density Study Summary ====="
echo "source: ${CSV}"
echo ""

column -t -s',' "${CSV}" 2>/dev/null || cat "${CSV}"

echo ""
echo "----- Trends (requires numeric CSV) -----"
awk -F',' '
NR == 1 { next }
{
  d = $1 + 0
  pps = $3 + 0
  nbr = $4 + 0
  orig = $5 + 0
  lat = $6 + 0
  thr = $8 + 0
  if (pps > 0) { sum_pps += pps; n++ }
  if (nbr >= 0) { sum_nbr += nbr }
  if (orig >= 0) { sum_orig += orig }
  if (lat > 0) { sum_lat += lat }
  if (thr > 0) { sum_thr += thr; if (min_thr == 0 || thr < min_thr) min_thr = thr; if (thr > max_thr) max_thr = thr }
}
END {
  if (n > 0) {
    printf("avg_batman_pps: %.2f\n", sum_pps / n)
    printf("avg_neighbors: %.1f\n", sum_nbr / n)
    printf("avg_originators: %.1f\n", sum_orig / n)
  }
  if (sum_lat > 0) printf("avg_latency_ms: %.2f\n", sum_lat / n)
  if (sum_thr > 0) {
    printf("avg_throughput_mbps: %.2f\n", sum_thr / n)
    printf("throughput_range_mbps: %.2f - %.2f\n", min_thr, max_thr)
  }
  print ""
  print "Tip: plot density vs batman_pps, neighbors, ping_avg_ms, throughput_mbps."
}' "${CSV}"
