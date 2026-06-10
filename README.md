# BATMAN-Adv ELP Impact Analysis

Simulation MANET Docker (**3 nœuds**) pour analyser le trafic ELP/BATMAN et son impact sur débit et latence.

## Cloner le projet

```bash
git clone https://github.com/mostafaguellil/Batman-ADV-ELP-Impact-Analysis.git
cd Batman-ADV-ELP-Impact-Analysis
```

## Démarrage

```bash
sudo modprobe batman-adv          # sur l'hôte Linux (obligatoire pour BATMAN)
./scripts/start_lab.sh            # node1, node2, node3 + bat0
```

Si le module manque sur l'hôte :

```bash
sudo apt install linux-modules-extra-$(uname -r)
sudo modprobe batman-adv
./scripts/start_lab.sh
```

Sans BATMAN (connectivité Docker seulement) :

```bash
./scripts/setup_batman.sh fallback --skip-compose
```

Étude complète :

```bash
./scripts/run_study.sh
```

## Scripts

| Script | Rôle |
|--------|------|
| `start_lab.sh` | Démarre 3 nœuds + configure BATMAN-Adv |
| `setup_batman.sh` | Setup manuel (`auto` / `batman` / `fallback`) |
| `run_study.sh` | Benchmark densité + random walk + analyse |
| `density_benchmark.sh` | Mesures par densité (2 ou 3 nœuds actifs) |
| `random_walk.sh` | Churn sur `node3` + CSV |
| `observe_batman.sh` | `batctl n/o`, trafic `0x4305` |
| `fault.sh` | Fautes manuelles (disconnect, netem) |

Config : `scripts/lib.sh` (`NODE_COUNT=3`)

## Observer BATMAN

```bash
./scripts/observe_batman.sh node1 all
./scripts/observe_batman.sh node1 watch
```

## Fautes manuelles

```bash
./scripts/fault.sh disconnect node3
./scripts/fault.sh reconnect node3
```

## Prérequis

- Linux + module `batman-adv` chargé sur **l'hôte** (pas dans le conteneur)
- Docker Compose

## Rapport

**[docs/TRAVAIL.md](docs/TRAVAIL.md)**

## Dépannage ping « Destination Host Unreachable »

BATMAN exige **aucune IP sur `eth0`** (seulement sur `bat0`). Le setup flush `eth0` et attache `eth0` à `bat0` via le kernel (`ip link set master bat0`).

Cause fréquente sous Docker : **multicast snooping** sur le bridge bloque les OGMs BATMAN. Le script désactive cela automatiquement (`tune_manet_bridge`).

```bash
git pull
sudo modprobe batman-adv
docker compose down
./scripts/start_lab.sh          # recrée le réseau manet + tune le bridge
./scripts/debug_mesh.sh         # multicast_snooping doit être 0
docker exec node1 bash -lc "batctl n"    # doit lister node2 et node3
docker exec node1 bash -lc "ping -c 3 10.0.0.2"
```

Si BATMAN reste impossible sur votre VM, `start_lab.sh` bascule en **fallback** (IPs sur eth0, pas de vrai BATMAN/ELP).

## Nettoyage

```bash
docker compose down
docker rm -f node1 node2 node3 2>/dev/null || true
```
