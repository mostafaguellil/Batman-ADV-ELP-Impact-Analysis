# BATMAN-Adv ELP Impact Analysis

Simulation MANET Docker (**3 nœuds**) pour analyser le trafic ELP/BATMAN et son impact sur débit et latence.

## Cloner le projet

```bash
git clone https://github.com/mostafaguellil/Batman-ADV-ELP-Impact-Analysis.git
cd Batman-ADV-ELP-Impact-Analysis
```

## Démarrage (Ubuntu)

```bash
sudo apt update
sudo apt install -y docker.io docker-compose-v2 batctl kmod
sudo apt install -y linux-modules-extra-$(uname -r)   # si batman-adv absent
sudo modprobe batman-adv
sudo usermod -aG docker "$USER"   # puis reconnecter la session
git pull
docker compose down
./scripts/start_lab.sh
```

Le lab utilise un réseau **macvlan** sur l'interface dummy `manet0` (L2 propre pour BATMAN). Les IPs mesh sont sur `bat0` (`10.0.0.1`–`10.0.0.3`), pas sur `eth0`.

`start_lab.sh` lance `docker compose build` sur l'hôte (internet requis une fois) — les conteneurs macvlan n'ont pas accès à apt en runtime.

**VMware / VirtualBox :** activer **Promiscuous Mode = Allow** sur la carte réseau de la VM.

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

```bash
./scripts/debug_mesh.sh
docker exec node1 bash -lc "batctl meshif bat0 n"   # 2 voisins (MAC)
docker exec node1 bash -lc "batctl meshif bat0 o"   # 10.0.0.2 et 10.0.0.3
docker exec node1 bash -lc "batctl meshif bat0 ping -c 3 10.0.0.2"
```

Si `batctl n` est vide : vérifier `lsmod | grep batman_adv`, promiscuous mode VM, puis `docker compose down && ./scripts/start_lab.sh`.

## Nettoyage

```bash
docker compose down
docker rm -f node1 node2 node3 2>/dev/null || true
```
