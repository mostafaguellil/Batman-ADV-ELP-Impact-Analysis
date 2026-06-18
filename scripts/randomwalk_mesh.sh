#!/usr/bin/env bash
# Wrapper — see mesh_exam_demo.sh
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "${1:-}" == "--real" ]]; then
  shift
  exec "${ROOT}/scripts/random_walk.sh" "$@"
fi
exec "${ROOT}/scripts/mesh_exam_demo.sh" "$@"
