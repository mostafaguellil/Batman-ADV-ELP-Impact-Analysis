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

## Nettoyage

```bash
docker compose down
docker rm -f node4 node5 node6 node7 node8 node9 node10 2>/dev/null || true
```
