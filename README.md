# BATMAN-Adv ELP Impact Analysis

Mini projet étudiant pour simuler un réseau MANET avec Docker et BATMAN-Adv.

## Objectif

Créer **30 noeuds** (`node1` … `node30`) en conteneurs sur un même bridge L2 (`manet`), activer `bat0` sur `10.0.0.0/24`, puis tester:
- la connectivité (`ping`)
- le débit (`iperf3`)
- la capture du trafic BATMAN/ELP (`tcpdump`)

## Fichiers du projet

- `docker-compose.yml` — 30 noeuds MANET
- `docs/TRAVAIL.md` — rapport (etat de l'art, methodologie, analyse)
- `scripts/lab_config.sh` — topologie partagee
- `scripts/start_lab.sh` / `setup_batman.sh` — demarrage et configuration
- `scripts/run_elp_study.sh` — etude ELP complete
- `scripts/elp_density_benchmark.sh` — mesures par densite
- `scripts/mesh_fault.sh` / `mesh_random_walk.sh` — fautes et churn

## Prerequis

- Un hote Linux avec Docker et Docker Compose
- Module noyau `batman-adv` disponible
- Acces `sudo` pour charger le module
- Ressources suffisantes pour **30 conteneurs** (RAM/CPU; prevoyez plusieurs Go de RAM)

### Important

- **macOS (Darwin)**: non supporte en natif pour `batman-adv`
- **Windows**: possible via WSL2/VM Linux si le module `batman-adv` est disponible

## Lancement rapide

**Tout-en-un (recommande):** demarre les 30 noeuds Docker, installe les outils, assigne les IP de test, lance `iperf3 -s` sur `node2`.

```bash
git clone https://github.com/mostafaguellil/batman-adv-elp-impact-analysis.git
cd batman-adv-elp-impact-analysis
./scripts/start_lab.sh
```

**Etape par etape:**

```bash
./scripts/setup_batman.sh
```

Modes disponibles:

- `./scripts/setup_batman.sh auto` (defaut): Linux -> BATMAN-Adv, macOS -> fallback Docker
- `./scripts/setup_batman.sh batman`: force le mode BATMAN-Adv (Linux uniquement)
- `./scripts/setup_batman.sh fallback`: test rapide Docker (connectivite/iperf/tcpdump) sans module batman-adv
- `./scripts/setup_batman.sh auto --skip-compose`: ne relance pas Compose (utilise par `start_lab.sh` apres `docker compose up`)

## Verification manuelle

### 1) Etat des conteneurs

```bash
docker compose ps
```

### 2) Verification bat0

```bash
docker exec node1 bash -lc "batctl if && ip -4 addr show bat0"
docker exec node15 bash -lc "batctl if && ip -4 addr show bat0"
docker exec node30 bash -lc "batctl if && ip -4 addr show bat0"
```

### 3) Ping entre noeuds

```bash
docker exec node1 bash -lc "ping -c 3 10.0.0.2"
docker exec node1 bash -lc "ping -c 3 10.0.0.15"
docker exec node1 bash -lc "ping -c 3 10.0.0.30"
```

### 4) Observation BATMAN-Adv

```bash
docker exec node1 bash -lc "batctl n"
docker exec node1 bash -lc "batctl o"
```

### 5) Test iperf3

Terminal 1:
```bash
docker exec -it node2 bash -lc "iperf3 -s"
```

Terminal 2:
```bash
docker exec node1 bash -lc "iperf3 -c 10.0.0.2 -t 10"
```

### 6) Capture trafic BATMAN/ELP

```bash
docker exec -it node1 bash -lc "tcpdump -i eth0 -nn -vv ether proto 0x4305"
```

## Injection de fautes mesh (Solution 1 + Solution 2)

Script unifie: `./scripts/mesh_fault.sh` — reutilise le reseau Compose `manet`, les noeuds `node1`…`node30`, et l interface underlay `eth0` (hardif BATMAN-adv).

**Solution 1 — perte totale de lien (Docker L2):**

```bash
./scripts/mesh_fault.sh disconnect node3
./scripts/mesh_fault.sh reconnect node3
```

Equivalent manuel:

```bash
docker network disconnect <project>_manet node3
docker network connect <project>_manet node3
```

**Solution 2 — degradation realiste (`tc netem` sur `eth0`):**

```bash
./scripts/mesh_fault.sh degrade node5 15 80 20   # 15% loss, 80 ms delay, 20 ms jitter
./scripts/mesh_fault.sh reset node5
./scripts/mesh_fault.sh reset-all
```

Equivalent manuel:

```bash
docker exec node5 tc qdisc replace dev eth0 root netem loss 15% delay 80ms 20ms
docker exec node5 tc qdisc del dev eth0 root || true
```

**Mode aleatoire** (deconnecte ou degrade des noeuds candidats `node3`…`node30`, puis reset a chaque round):

```bash
./scripts/mesh_fault.sh random 10 15 2   # 10 rounds, 15 s entre rounds, 2 noeuds max
```

Observer l impact BATMAN-adv pendant les fautes:

```bash
docker exec node1 bash -lc "batctl n; batctl o"
docker exec node1 bash -lc "ping -c 3 10.0.0.2"
```

**Random walk automatise (disconnect + analyse ELP/BATMAN):**

```bash
./scripts/mesh_random_walk.sh 20 10 10 5
# ou tout l'etude :
./scripts/run_elp_study.sh
```

Chaque step genere une ligne CSV : trafic BATMAN/ELP (`0x4305`), voisins (`batctl n`), originateurs (`batctl o`), latence, debit — phases `during_disconnect` et `after_reconnect`.

```bash
./scripts/summarize_random_walk.sh results/mesh_random_walk_*.csv
./scripts/analyze_study.sh
```

### Observer le comportement BATMAN en direct

```bash
./scripts/observe_batman.sh node1 all          # etat complet
./scripts/observe_batman.sh node1 neighbors    # table ELP (voisins)
./scripts/observe_batman.sh node1 routes       # table OGM (routage)
./scripts/observe_batman.sh node1 traffic 30   # trames 0x4305 en live
./scripts/observe_batman.sh node1 watch        # rafraichit n/o toutes les 3s
```

| Commande | Ce que tu vois |
|----------|----------------|
| `batctl n` | Voisins ELP — qui est a 1 saut, qualite du lien |
| `batctl o` | Originateurs OGM — routes vers chaque noeud du mesh |
| `tcpdump … 0x4305` | Trafic de controle BATMAN (OGM + ELP) sur `eth0` |
| `batctl if` | Interfaces physiques attachees a `bat0` |

Pendant un random walk, lance `observe_batman.sh node1 watch` dans un 2e terminal : les voisins/originateurs changent quand un noeud est deconnecte.

## Etude ELP — plan de travail complet

Document academique : **[docs/TRAVAIL.md](docs/TRAVAIL.md)**

| Section du rapport | Contenu |
|--------------------|---------|
| Etat de l'art | MANET, BATMAN-Adv, ELP, travaux connexes |
| Fonctionnement BATMAN-Adv | OGM, ELP, architecture, diagnostic |
| Environnement virtuel | 30 noeuds Docker, bridge `manet`, `bat0` |
| Evaluation densite | Scripts automatises ci-dessous |
| Impact debit / latence | iperf3 + ping par niveau de densite |
| Perspectives | Optimisations, travail futur |

### Lancer l'etude complete (Linux, 100% automatise)

```bash
./scripts/run_elp_study.sh        # densite 5..30 + random walk + analyse
./scripts/run_elp_study.sh 30     # 30 steps de random walk
```

### Etape par etape

```bash
./scripts/start_lab.sh
./scripts/elp_density_benchmark.sh              # densites 5,10,15,20,25,30
./scripts/summarize_elp_benchmark.sh results/elp_density_*.csv
```

Metriques collectees par densite : paquets BATMAN/ELP (`0x4305`), paquets/s, voisins `batctl n`, latence ping, debit iperf3.

```bash
./scripts/set_mesh_density.sh 15   # activer seulement node1..node15
```

## Nettoyage

```bash
docker compose down
```

## Erreurs courantes

- `Current host: Darwin`: execute sur macOS, passer sur Linux/VM Linux
- `modprobe: command not found`: `kmod` manquant sur l hote Linux
- `Module batman-adv not found`: noyau Linux sans support `batman-adv`
- `docker compose is not available`: installer le plugin Docker Compose sur la VM Linux
- `sudo requires a password`: executer `sudo -v` puis relancer le script
- `Cannot connect to Docker daemon`: demarrer Docker Desktop/Engine puis relancer
