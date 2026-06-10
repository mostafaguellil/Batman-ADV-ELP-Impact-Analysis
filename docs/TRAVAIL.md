# Analyse de l'impact d'ELP dans BATMAN-Adv

## 1. Problématique

BATMAN-Adv utilise **ELP** (Echo Link Protocol) pour la découverte de voisins et l'estimation de qualité de lien. Ce trafic de contrôle croît avec la densité du réseau et peut dégrader débit et latence.

**Objectifs :** quantifier le trafic ELP/BATMAN, mesurer débit/latence, proposer des pistes d'optimisation.

## 2. État de l'art

- **MANET** : réseaux ad-hoc sans infrastructure, topologie dynamique.
- **BATMAN-Adv** : routage couche 2, interface `bat0`, module noyau Linux.
- **ELP** : probes de voisinage à 1 saut ; coexiste avec les **OGM** (routage).
- **Travaux connexes** : compromis fraîcheur topologie vs surcharge du médium.

Références : [open-mesh.org](https://www.open-mesh.org/projects/batman-adv/wiki), documentation noyau `batman-adv`.

## 3. Fonctionnement BATMAN-Adv

```
Applications → bat0 (10.0.0.x) → BATMAN-Adv (OGM + ELP) → eth0 (bridge Docker)
```

| Mécanisme | Rôle | Commande |
|-----------|------|----------|
| ELP | Voisins + qualité lien | `batctl n` |
| OGM | Tables de routage | `batctl o` |
| Contrôle | Trafic mesh | `tcpdump -i eth0 ether proto 0x4305` |

## 4. Environnement de test

- **3 nœuds** `node1`, `node2`, `node3` sur bridge `manet`
- **Client** `node1`, **serveur iperf** `node2`, **churn** `node3`
- Module `batman-adv` chargé sur **l'hôte Linux** (`sudo modprobe batman-adv`)

### Installation

```bash
git clone https://github.com/mostafaguellil/Batman-ADV-ELP-Impact-Analysis.git
cd Batman-ADV-ELP-Impact-Analysis
sudo modprobe batman-adv
./scripts/start_lab.sh
./scripts/run_study.sh
```

## 5. Méthodologie

### Benchmark densité
Pour N = 2 ou 3 nœuds actifs : convergence 20s, capture tcpdump 15s, ping, iperf3.

### Random walk
Un nœud déconnecté/reconnecté à la fois ; métriques `during_disconnect` vs `after_reconnect`.

### Métriques CSV
`batman_packets`, `batman_pps`, `neighbors`, `originators`, `ping_avg_ms`, `throughput_mbps`

## 6. Résultats (à remplir)

| Densité | PPS | Voisins | Latence (ms) | Débit (Mbit/s) |
|---------|-----|---------|--------------|----------------|
| 2 | | | | |
| 3 | | | | |

Fichiers : `results/density_*.csv`, `results/random_walk_*.csv`

## 7. Analyse

- Trafic contrôle croît avec la densité sur bridge L2 plat (tous voisins à 1 saut).
- Débit/latence corrélés à la charge de contrôle.
- **Limites** : bridge Docker ≠ radio WiFi ; résultats comparatifs.

## 8. Perspectives

- Ajuster `elp_interval` sur réseaux denses
- Topologies multi-sauts (chaîne/grille)
- Tests avec `tc netem` (perte, délai)
- Validation sur hardware WiFi

## 9. Scripts

```
scripts/lib.sh              # config + fautes + métriques
scripts/start_lab.sh        # démarrage
scripts/run_study.sh        # étude complète
scripts/density_benchmark.sh
scripts/random_walk.sh
scripts/summarize_results.sh
scripts/observe_batman.sh
scripts/fault.sh
```
