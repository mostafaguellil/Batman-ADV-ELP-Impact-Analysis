#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./scripts/summarize_random_walk.sh <results/mesh_random_walk_*.csv>

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <mesh_random_walk.csv>"
  exit 1
fi

CSV="$1"
if [[ ! -f "${CSV}" ]]; then
  echo "ERROR: file not found: ${CSV}" >&2
  exit 1
fi

echo "===== Random Walk — ELP/BATMAN Analysis ====="
echo "source: ${CSV}"
echo ""

column -t -s',' "${CSV}" 2>/dev/null || cat "${CSV}"

echo ""
echo "----- Aggregates by phase -----"
awk -F',' '
NR == 1 { next }
{
  phase = $3
  pps = $5 + 0
  nbr = $6 + 0
  orig = $7 + 0
  lat = $8 + 0
  loss = $9 + 0
  thr = $10 + 0

  cnt[phase]++
  if (pps > 0) { pps_sum[phase] += pps; pps_n[phase]++ }
  if (nbr >= 0) { nbr_sum[phase] += nbr; nbr_n[phase]++ }
  if (orig >= 0) { orig_sum[phase] += orig; orig_n[phase]++ }
  if (lat > 0) { lat_sum[phase] += lat; lat_n[phase]++ }
  if (thr > 0) { thr_sum[phase] += thr; thr_n[phase]++ }
  if (loss >= 0) { loss_sum[phase] += loss; loss_n[phase]++ }
}
END {
  for (p in cnt) {
    printf("\n[%s] samples=%d\n", p, cnt[p])
    if (pps_n[p] > 0) printf("  avg_batman_pps: %.2f\n", pps_sum[p] / pps_n[p])
    if (nbr_n[p] > 0) printf("  avg_neighbors: %.1f\n", nbr_sum[p] / nbr_n[p])
    if (orig_n[p] > 0) printf("  avg_originators: %.1f\n", orig_sum[p] / orig_n[p])
    if (lat_n[p] > 0) printf("  avg_latency_ms: %.2f\n", lat_sum[p] / lat_n[p])
    if (loss_n[p] > 0) printf("  avg_ping_loss_pct: %.2f\n", loss_sum[p] / loss_n[p])
    if (thr_n[p] > 0) printf("  avg_throughput_mbps: %.2f\n", thr_sum[p] / thr_n[p])
  }
}' "${CSV}"

echo ""
echo "----- Churn impact (during_disconnect vs after_reconnect) -----"
awk -F',' '
NR == 1 { next }
$3 == "during_disconnect" {
  d_pps[NR]=$5+0; d_lat[NR]=$8+0; d_thr[NR]=$10+0; d_nbr[NR]=$6+0; d_step[NR]=$1
}
$3 == "after_reconnect" {
  r_pps[$1]=$5+0; r_lat[$1]=$8+0; r_thr[$1]=$10+0; r_nbr[$1]=$6+0
}
END {
  n=0; sum_dpps=0; sum_rpps=0; sum_dlat=0; sum_rlat=0; sum_dthr=0; sum_rthr=0
  for (i in d_step) {
    s = d_step[i]
    if (s in r_pps) {
      n++
      sum_dpps += d_pps[i]; sum_rpps += r_pps[s]
      if (d_lat[i]>0 && r_lat[s]>0) { sum_dlat += d_lat[i]; sum_rlat += r_lat[s] }
      if (d_thr[i]>0 && r_thr[s]>0) { sum_dthr += d_thr[i]; sum_rthr += r_thr[s] }
    }
  }
  if (n > 0) {
    printf("paired_steps: %d\n", n)
    printf("avg_batman_pps: disconnect=%.2f reconnect=%.2f\n", sum_dpps/n, sum_rpps/n)
    if (sum_dlat > 0) printf("avg_latency_ms: disconnect=%.2f reconnect=%.2f\n", sum_dlat/n, sum_rlat/n)
    if (sum_dthr > 0) printf("avg_throughput_mbps: disconnect=%.2f reconnect=%.2f\n", sum_dthr/n, sum_rthr/n)
  } else {
    print "No paired steps found."
  }
}' "${CSV}"
