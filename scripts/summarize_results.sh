#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./scripts/summarize_results.sh              # latest results
#   ./scripts/summarize_results.sh density <csv>
#   ./scripts/summarize_results.sh walk <csv>

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE="${1:-all}"
FILE="${2:-}"

summarize_density() {
  local csv="$1"
  echo "===== Density benchmark ====="
  echo "source: ${csv}"
  echo ""
  column -t -s',' "${csv}" 2>/dev/null || cat "${csv}"
  echo ""
  awk -F',' 'NR>1{pps+=$3;n++;nbr+=$4;orig+=$5; if($6>0)lat+=$6; if($8>0)thr+=$8}
    END{if(n){printf("avg_pps=%.2f neighbors=%.1f originators=%.1f latency_ms=%.2f throughput_mbps=%.2f\n",pps/n,nbr/n,orig/n,lat/n,thr/n)}}' "${csv}"
}

summarize_walk() {
  local csv="$1"
  echo "===== Random walk ====="
  echo "source: ${csv}"
  echo ""
  column -t -s',' "${csv}" 2>/dev/null || cat "${csv}"
  echo ""
  awk -F',' '
    NR==1{next}
    {
      pps[$3]+=$5; nbr[$3]+=$6; orig[$3]+=$7; c[$3]++
      if ($9 != "NA" && $9+0 >= 0) loss[$3]+=$9
      if ($8 != "NA" && $8+0 > 0) lat[$3]+=$8
      if ($10 != "NA" && $10+0 > 0) thr[$3]+=$10
    }
    END {
      for (p in c) {
        printf("[%s] samples=%d pps=%.2f neighbors=%.1f originators=%.1f latency=%.2f loss%%=%.1f throughput=%.2f\n",
          p, c[p], pps[p]/c[p], nbr[p]/c[p], orig[p]/c[p],
          (lat[p] ? lat[p]/c[p] : 0), (loss[p] ? loss[p]/c[p] : 0), (thr[p] ? thr[p]/c[p] : 0))
      }
    }' "${csv}"
}

case "${MODE}" in
  density)
    [[ -n "${FILE}" ]] || { echo "Usage: $0 density <csv>" >&2; exit 1; }
    summarize_density "${FILE}"
    ;;
  walk)
    [[ -n "${FILE}" ]] || { echo "Usage: $0 walk <csv>" >&2; exit 1; }
    summarize_walk "${FILE}"
    ;;
  all|*)
    d="$(ls -t "${ROOT}"/results/density_*.csv 2>/dev/null | head -1 || true)"
    w="$(ls -t "${ROOT}"/results/random_walk_*.csv 2>/dev/null | head -1 || true)"
    [[ -n "${d}" ]] && { summarize_density "${d}"; echo ""; }
    [[ -n "${w}" ]] && summarize_walk "${w}"
    [[ -z "${d}" && -z "${w}" ]] && echo "No results in results/. Run ./scripts/run_study.sh"
    ;;
esac
