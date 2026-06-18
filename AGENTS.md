# AGENTS.md

## Cursor Cloud specific instructions

### What this repo is

BATMAN-Adv ELP Impact Analysis: a Docker-based MANET simulation lab (30 Ubuntu containers on a `manet` bridge) used to benchmark mesh density, churn, latency, and throughput. There is no web UI, database, or language package manager at the repo root — orchestration is Bash + Docker Compose.

### Docker daemon

The cloud VM does not start Docker automatically. Before any lab command:

```bash
# Start once per VM session (if `docker info` fails)
sudo dockerd > /tmp/dockerd.log 2>&1 &
sleep 2
sudo chmod 666 /var/run/docker.sock   # if permission denied
```

Docker is configured with `fuse-overlayfs` storage driver (`/etc/docker/daemon.json`).

### BATMAN-Adv vs fallback mode

`./scripts/start_lab.sh` calls `setup_batman.sh auto`, which selects **batman** mode on Linux and requires the host `batman-adv` kernel module (`modprobe batman-adv`). The Cursor Cloud VM kernel (`6.1.147`) does **not** ship `batman-adv`, so `start_lab.sh` will fail at the modprobe step.

Use **fallback mode** instead (assigns overlay IPs on `eth0`; ping/iperf/tcpdump work, but not real BATMAN/ELP):

```bash
./scripts/setup_batman.sh fallback
```

Then start the iperf3 server if needed:

```bash
docker exec -d node2 bash -lc 'iperf3 -s'
```

On a full Linux host with `batman-adv`, use `./scripts/start_lab.sh` or `./scripts/setup_batman.sh batman`.

### First-time lab startup

- Pulls `ubuntu:22.04` and runs `apt-get install` inside all 30 containers (~3 minutes).
- Requires passwordless `sudo` (available in cloud VM).

### Quick verification

```bash
docker exec node1 bash -lc "ping -c 3 10.0.0.2"
docker exec node1 bash -lc "iperf3 -c 10.0.0.2 -t 5"
docker ps --format '{{.Names}}' | wc -l   # expect 30
```

### Tear down

```bash
docker compose down
```

### Key scripts

See `README.md` for `run_study.sh`, `density_benchmark.sh`, `random_walk.sh`, `observe_batman.sh`, and `fault.sh`. Full automated studies need real BATMAN mode; in fallback mode, density/random-walk scripts run but BATMAN-specific metrics (`batctl`, ELP packet counts) will be empty or zero.
