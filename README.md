# BATMAN-Adv ELP Impact Analysis

Simulation MANET Docker (**10 nœuds**) pour analyser le trafic ELP/BATMAN et son impact sur débit et latence.

## Cloner le projet

```bash
git clone https://github.com/mostafaguellil/Batman-ADV-ELP-Impact-Analysis.git
cd Batman-ADV-ELP-Impact-Analysis
```

## Démarrage

```bash
./scripts/start_lab.sh          # lance les 10 nœuds + configure bat0
```

Sur **Linux**, le script peut demander ton mot de passe `sudo` une fois pour charger `batman-adv` sur l’hôte. Si tu préfères le faire manuellement :

```bash
sudo modprobe batman-adv
./scripts/start_lab.sh
```

Sans BATMAN (connectivité Docker seulement) :

```bash
./scripts/setup_batman.sh fallback --skip-compose
```

Puis l’étude complète :

```bash
./scripts/run_study.sh
```

## Scripts

| Script | Rôle |
|--------|------|
| `start_lab.sh` | Démarre Docker + configure BATMAN-Adv |
| `setup_batman.sh` | Setup manuel (`auto` / `batman` / `fallback`) |
| `run_study.sh` | Benchmark densité + random walk + analyse |
| `density_benchmark.sh` | Mesures ELP/BATMAN par densité (3→10) |
| `random_walk.sh` | Churn aléatoire disconnect/reconnect + CSV |
| `summarize_results.sh` | Résumé des CSV dans `results/` |
| `observe_batman.sh` | Observer `batctl n/o` et trafic `0x4305` |
| `fault.sh` | Fautes manuelles (disconnect, netem) |

Bibliothèque partagée : `scripts/lib.sh` (`NODE_COUNT=10`)

## Observer BATMAN

```bash
./scripts/observe_batman.sh node1 all
./scripts/observe_batman.sh node1 neighbors
./scripts/observe_batman.sh node1 routes
./scripts/observe_batman.sh node1 traffic 30
./scripts/observe_batman.sh node1 watch
```

## Fautes manuelles

```bash
./scripts/fault.sh disconnect node5
./scripts/fault.sh reconnect node5
./scripts/fault.sh degrade node5 10 50 10
./scripts/fault.sh reset-all
```

## Prérequis

- Linux + module `batman-adv` + Docker Compose
- macOS : mode fallback uniquement (pas de vrai BATMAN)

## Rapport

**[docs/TRAVAIL.md](docs/TRAVAIL.md)**

## Nettoyage

```bash
docker compose down
# supprimer d’anciens conteneurs node11..node30 si encore présents :
docker rm -f node11 node12 node13 node14 node15 node16 node17 node18 node19 node20 \
  node21 node22 node23 node24 node25 node26 node27 node28 node29 node30 2>/dev/null || true
```
