#!/usr/bin/env bash
set -euo pipefail

# Exam demo part 1 (~1–2 min): environment + 30 container creation (print only).
# Usage: ./scripts/env_setup_demo.sh [duration_secs]
# Real lab: ./scripts/env_setup_demo.sh --real

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_SECS="${1:-90}"
if [[ "${1:-}" == "--real" ]]; then
  exec "${ROOT}/scripts/start_lab.sh"
fi
[[ "${TARGET_SECS}" =~ ^[0-9]+$ ]] || TARGET_SECS=90
(( TARGET_SECS < 60 )) && TARGET_SECS=60
(( TARGET_SECS > 120 )) && TARGET_SECS=120

NODE_COUNT=30
BATCH=6
IMAGE="batman-manet-node:22.04"
LOG_DIR="${ROOT}/results"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="${LOG_DIR}/env_setup_demo_${TS}.log"

mkdir -p "${LOG_DIR}"
START=$SECONDS

say() { echo "[$(date '+%F %T')] $*" | tee -a "${OUT}"; }
dim() { echo "    $*" | tee -a "${OUT}"; }
hdr() { echo "" | tee -a "${OUT}"; echo "==> $*" | tee -a "${OUT}"; }

wait_secs() {
  local total="$1" msg="${2:-}" i
  [[ -n "${msg}" ]] && printf '%s' "${msg}" | tee -a "${OUT}"
  for ((i = 0; i < total; i++)); do
    printf '.' | tee -a "${OUT}"
    sleep 1
  done
  echo "" | tee -a "${OUT}"
}

fake_container_id() {
  awk -v n="$1" -v seed="${RANDOM}" 'BEGIN{
    srand(seed+n); printf "a%07x%04x", int(rand()*0xfffffff), n*17
  }'
}

show_docker_ps() {
  hdr "Running containers (${NODE_COUNT}/${NODE_COUNT})"
  dim "NAMES     IMAGE                    STATUS          NETWORKS"
  local i id
  for i in $(seq 1 "${NODE_COUNT}"); do
    id="$(fake_container_id "${i}")"
    dim "node${i}     ${IMAGE}   Up $(($i / 3 + 1)) minutes   manet"
    sleep 0.08
  done
}

# --- main ---
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  BATMAN-Adv MANET Lab — Part 1: Environment setup            ║"
echo "║  Docker + macvlan manet0 + 30 nodes (node1..node30)          ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

say "Environment setup demo (target ~${TARGET_SECS}s, simulated)"

hdr "Preflight checks"
dim "OS ......................... Ubuntu 22.04 LTS (Linux x86_64)"
dim "docker ..................... Docker Engine 24.0.7"
dim "docker compose ............. v2.24.1"
dim "batctl ....................... 2023.3"
wait_secs 2 "Connecting to Docker daemon"

hdr "Host BATMAN prerequisites"
dim "sudo modprobe batman-adv"
dim "lsmod | grep batman_adv"
dim "batman_adv            212992  0"
dim "sudo ip link add manet0 type dummy"
dim "sudo ip link set manet0 up"
dim "net.bridge.bridge-nf-call-iptables = 0"
dim "net.ipv4.conf.all.rp_filter = 0"
wait_secs 2 "Loading kernel modules"

hdr "Building Docker image (batman-manet-node:22.04)"
dim "[1/6] FROM ubuntu:22.04"
dim "[2/6] RUN apt-get update && apt-get install -y batctl iperf3 tcpdump iproute2 ping"
wait_secs 3 "Installing packages in image"
dim "[3/6] COPY entrypoint scripts"
dim "[4/6] RUN chmod +x /usr/local/bin/*"
dim "[5/6] exporting to image"
dim "[6/6] naming to docker.io/library/${IMAGE}"
dim "Successfully built ${IMAGE}"
wait_secs 2 "docker compose build"

hdr "Creating L2 network (macvlan on manet0)"
dim "docker network create batman-adv-elp-impact-analysis_manet"
dim "  driver: macvlan"
dim "  parent: manet0"
dim "  macvlan_mode: bridge"
dim "  subnet: 172.30.255.0/24 (underlay — IPs on bat0 later)"
wait_secs 2 "Provisioning manet network"

elapsed=$((SECONDS - START))
remain=$((TARGET_SECS - elapsed - 25))
(( remain < 25 )) && remain=25
batch_pause=$((remain / 7))
(( batch_pause < 3 )) && batch_pause=3
(( batch_pause > 8 )) && batch_pause=8

hdr "Starting ${NODE_COUNT} containers (batched compose up)"
dim "Strategy: node1 first (creates network), then batches of ${BATCH}"
dim ""

dim "    step 1/2: node1 (create manet network)"
dim "    docker compose up -d --no-build node1"
dim "    Container node1  Started  $(fake_container_id 1)"
wait_secs "${batch_pause}" "Attaching node1 to macvlan"

local_start=2
batch_num=1
while [[ "${local_start}" -le "${NODE_COUNT}" ]]; do
  local_end=$((local_start + BATCH - 1))
  (( local_end > NODE_COUNT )) && local_end="${NODE_COUNT}"
  svc=""
  for ((i = local_start; i <= local_end; i++)); do
    svc+=" node${i}"
  done
  dim ""
  dim "    step 2/2 batch ${batch_num}:${svc}"
  for ((i = local_start; i <= local_end; i++)); do
    dim "    Container node${i}  Started  $(fake_container_id "${i}")"
    sleep 0.2
  done
  wait_secs "${batch_pause}" "Starting batch ${batch_num}"
  local_start=$((local_end + 1))
  batch_num=$((batch_num + 1))
done

hdr "Verifying stack"
dim "docker compose ps --status running -q | wc -l"
dim "${NODE_COUNT}"
dim "Container tools OK (batctl, iproute2, iperf3, tcpdump, ping)"
wait_secs 2 "Health check"

show_docker_ps

hdr "Environment ready"
dim "30 containers on network 'manet' (macvlan/manet0)"
dim "Mesh IPs will be assigned on bat0: 10.0.0.1 – 10.0.0.30 (Part 2)"
dim "Roles: node1=client/observer | node2=iperf server | node3..30=relay"

elapsed=$((SECONDS - START))
say "Setup complete in ${elapsed}s (simulated)"
echo ""
echo "Next step (BATMAN + random walk demo):"
echo "  ./scripts/mesh_exam_demo.sh"
echo ""
echo "Full real lab:"
echo "  ./scripts/env_setup_demo.sh --real"
echo "  ./scripts/mesh_exam_demo.sh --real"
