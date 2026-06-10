# BATMAN-Adv ELP Impact Analysis

Simulation MANET Docker (30 nœuds) pour analyser le trafic ELP/BATMAN et son impact sur débit et latence.

## Cloner le projet

```bash
git clone https://github.com/mostafaguellil/Batman-ADV-ELP-Impact-Analysis.git
cd Batman-ADV-ELP-Impact-Analysis
```

## Démarrage

```bash
./scripts/start_lab.sh          # lance les 30 nœuds + configure bat0
./scripts/run_study.sh          # étude complète automatisée
```

## Scripts

| Script | Rôle |
|--------|------|
| `start_lab.sh` | Démarre Docker + configure BATMAN-Adv |
| `setup_batman.sh` | Setup manuel (`auto` / `batman` / `fallback`) |
| `run_study.sh` | Benchmark densité + random walk + analyse |
| `density_benchmark.sh` | Mesures ELP/BATMAN par densité (5→30) |
| `random_walk.sh` | Churn aléatoire disconnect/reconnect + CSV |
| `summarize_results.sh` | Résumé des CSV dans `results/` |
| `observe_batman.sh` | Observer `batctl n/o` et trafic `0x4305` |
| `fault.sh` | Fautes manuelles (disconnect, netem) |

Bibliothèque partagée : `scripts/lib.sh`

## Observer BATMAN

```bash
./scripts/observe_batman.sh node1 all        # état complet
./scripts/observe_batman.sh node1 neighbors # table ELP
./scripts/observe_batman.sh node1 routes     # table OGM
./scripts/observe_batman.sh node1 traffic 30 # trames contrôle
./scripts/observe_batman.sh node1 watch      # live (3s)
```

| Commande | Signification |
|----------|---------------|
| `batctl n` | Voisins ELP (1 saut) |
| `batctl o` | Routes OGM (originateurs) |
| `tcpdump … 0x4305` | Trafic contrôle BATMAN sur `eth0` |

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

Structure du rapport : **[docs/TRAVAIL.md](docs/TRAVAIL.md)**

## Nettoyage

```bash
docker compose down
```
