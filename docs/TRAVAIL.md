# Analyse de l'impact d'ELP dans BATMAN-Adv

Document de travail — structure du rapport et méthodologie expérimentale.

---

## 1. Introduction

### Problématique

Dans un réseau MANET (*Mobile Ad-hoc Network*), les nœuds coopèrent pour router les paquets sans infrastructure fixe. **BATMAN-Adv** (*Better Approach To Mobile Ad-hoc Networking — Advanced*) est un protocole de routage de couche 2 largement utilisé dans les réseaux mesh communautaires et militaires.

Le protocole **ELP** (*Echo Link Protocol*) est le mécanisme de **découverte de voisins** et d'**estimation de la qualité des liens** dans BATMAN-Adv IV. Il génère du trafic de contrôle proportionnel à la densité du réseau. Cette étude vise à :

1. Quantifier le trafic ELP/BATMAN selon la densité du réseau ;
2. Mesurer l'impact sur le **débit** et la **latence** ;
3. Identifier des pistes d'optimisation.

### Objectifs

| Objectif | Indicateur |
|----------|------------|
| Quantifier le trafic de contrôle | Paquets/s, octets/s (ethertype `0x4305`) |
| Évaluer la latence | RTT moyen, perte ICMP (`ping`) |
| Évaluer le débit | Débit TCP (`iperf3`, Mbit/s) |
| Corréler densité ↔ performance | Courbes densité / métriques |

---

## 2. État de l'art

### 2.1 Réseaux MANET

Un MANET est un réseau sans fil où chaque nœud peut router pour les autres. Les contraintes principales :

- **Topologie dynamique** : liens qui apparaissent/disparaissent ;
- **Bande passante limitée** : le trafic de contrôle consomme des ressources ;
- **Absence d'infrastructure** : pas de routeur central.

Protocoles de routage courants : **OLSR**, **AODV**, **Babel**, **BATMAN-Adv**.

### 2.2 BATMAN-Adv dans l'écosystème mesh

BATMAN-Adv opère en **couche 2** : il crée une interface virtuelle `bat0` et encapsule le trafic sur les interfaces physiques (*hard interfaces*). Avantages :

- Transparence IP (toute adresse peut être utilisée sur `bat0`) ;
- Routement par **meilleur chemin** basé sur la qualité des liens ;
- Intégration noyau Linux (`batman-adv` module).

Références : [BATMAN documentation](https://www.open-mesh.org/projects/batman-adv/wiki), Neumann et al., *BATMAN Advanced (BATMAN-Adv)*.

### 2.3 ELP — Echo Link Protocol

ELP remplace l'ancienne sonde unicast (*single-hop ping*) dans BATMAN-Adv IV.

| Aspect | Description |
|--------|-------------|
| **Rôle** | Découverte de voisins à 1 saut + mesure de qualité de lien |
| **Mécanisme** | Émission de probes ELP ; les voisins répondent avec des probes de réponse |
| **Fréquence** | Intervalle configurable (`elp_interval`, sysfs) |
| **Impact densité** | Plus de voisins ⇒ plus de probes/réponses ⇒ plus de trafic |

ELP coexiste avec les **OGM** (*Originator Messages*) qui diffusent l'état de routage. Le trafic capturé sur `ether proto 0x4305` regroupe OGM, ELP et autres trames BATMAN — indicateur du **plan de contrôle global**.

### 2.4 Travaux connexes sur le coût du trafic de contrôle

- Augmentation du trafic de contrôle avec la densité dans les protocoles proactifs ;
- Compromis entre **fraîcheur de la topologie** et **surcharge du médium** ;
- Études de performance BATMAN-Adv en environnement réel (Freifunk, etc.).

**Positionnement de ce projet** : évaluation reproductible en environnement virtuel Docker, avec variation contrôlée du nombre de nœuds actifs.

---

## 3. Fonctionnement de BATMAN-Adv

### 3.1 Architecture

```
┌─────────────────────────────────────────────┐
│  Applications (ping, iperf, TCP/UDP)        │
├─────────────────────────────────────────────┤
│  bat0  (interface mesh, IP 10.0.0.x/24)    │
├─────────────────────────────────────────────┤
│  BATMAN-Adv (module noyau batman-adv)       │
│    • OGM  → tables de routage               │
│    • ELP  → voisinage + qualité de lien     │
│    • Gateway / bridge loop avoidance        │
├─────────────────────────────────────────────┤
│  eth0  (hard interface — bridge Docker)     │
└─────────────────────────────────────────────┘
```

### 3.2 Messages OGM (Originator Messages)

- Chaque nœud diffuse périodiquement son **OGM** ;
- Les voisins le retransmettent (selon règles TQ — *Transmit Quality*) ;
- Construit la table `batctl o` (originateurs connus) ;
- Permet le routage multi-sauts.

### 3.3 Messages ELP (Echo Link Protocol)

- Probes envoyées aux adresses MAC des voisins potentiels ;
- Mesure du RTT et du taux de perte par lien ;
- Alimente `batctl n` (table de voisinage) ;
- Influence le choix du **next hop**.

### 3.4 Cycle de vie d'un paquet utilisateur

1. Paquet injecté sur `bat0` ;
2. BATMAN-Adv consulte la table de routage (`batctl o`) ;
3. Encapsulation dans une trame BATMAN sur `eth0` ;
4. Réception, décapsulation, livraison sur `bat0` du nœud destination.

### 3.5 Commandes de diagnostic

```bash
batctl if          # hard interfaces attachées
batctl n           # voisins (ELP)
batctl o           # originateurs (OGM / routage)
batctl ping <IP>   # ping mesh natif
tcpdump -i eth0 ether proto 0x4305   # trafic BATMAN/ELP
```

---

## 4. Environnement de test virtuel

### 4.1 Topologie

| Paramètre | Valeur |
|-----------|--------|
| Nœuds max | 30 (`node1` … `node30`) |
| Réseau Docker | `manet` (bridge L2) |
| Interface underlay | `eth0` |
| Overlay mesh | `bat0` / `10.0.0.0/24` |
| Client test | `node1` |
| Serveur iperf | `node2` |

### 4.2 Prérequis

- Hôte **Linux** avec module `batman-adv` ;
- Docker + Docker Compose ;
- `sudo` pour `modprobe batman-adv`.

### 4.3 Démarrage

```bash
./scripts/start_lab.sh
```

### 4.4 Variation de la densité

La densité = nombre de nœuds **actifs** sur le bridge. Le script `elp_density_benchmark.sh` connecte `node1…nodeN` et déconnecte `node(N+1)…node30` via `docker network disconnect` (perte L2 réaliste).

Niveaux testés par défaut : **5, 10, 15, 20, 25, 30** nœuds.

### 4.5 Injection de fautes (optionnel)

- `mesh_fault.sh` : déconnexion L2, dégradation `tc netem` ;
- `mesh_random_walk.sh` : churn aléatoire pour tester la convergence.

---

## 5. Méthodologie d'évaluation

### 5.1 Protocole expérimental

Pour chaque niveau de densité `N` :

1. **Configuration** : activer `N` nœuds, déconnecter les autres ;
2. **Convergence** : attendre 45 s (tables `batctl n/o` stabilisées) ;
3. **Trafic contrôle** : capture `tcpdump` 30 s sur `eth0`, filtre `0x4305` ;
4. **Latence** : `ping -c 30` de `node1` vers `node2` ;
5. **Débit** : `iperf3 -t 15` de `node1` vers `node2` ;
6. **Voisinage** : `batctl n` (nombre de voisins sur `node1`).

### 5.2 Lancement automatisé

```bash
./scripts/run_elp_study.sh
```

Ou manuellement :

```bash
./scripts/elp_density_benchmark.sh
./scripts/summarize_elp_benchmark.sh results/elp_density_*.log
```

### 5.3 Métriques collectées

| Métrique | Source | Unité |
|----------|--------|-------|
| `batman_packets` | tcpdump | paquets / fenêtre |
| `batman_pps` | calculé | paquets/s |
| `neighbor_count` | `batctl n` | nombre |
| `ping_avg_ms` | ping | ms |
| `ping_loss_pct` | ping | % |
| `throughput_mbps` | iperf3 | Mbit/s |

### 5.4 Modèle d'hypothèses

- **H1** : le trafic de contrôle croît avec la densité (au moins linéairement à 1 saut sur bridge plat) ;
- **H2** : la latence et le débit se dégradent quand le trafic de contrôle augmente ;
- **H3** : la convergence après churn est plus lente à forte densité.

---

## 6. Résultats (template)

> Remplir après exécution sur hôte Linux. Exemple de tableau :

| Densité | Paquets BATMAN (30s) | PPS | Voisins | Latence avg (ms) | Perte (%) | Débit (Mbit/s) |
|---------|----------------------|-----|---------|------------------|-----------|----------------|
| 5 | _à mesurer_ | | | | | |
| 10 | | | | | | |
| 15 | | | | | | |
| 20 | | | | | | |
| 25 | | | | | | |
| 30 | | | | | | |

### Graphiques suggérés

1. Densité vs paquets/s (trafic contrôle) ;
2. Densité vs débit ;
3. Densité vs latence ;
4. (Optionnel) Random walk : débit avant/après churn.

---

## 7. Analyse et interprétation

### 7.1 Trafic ELP / BATMAN

Sur un bridge L2 plat, chaque nœud voit tous les autres en 1 saut. Le trafic ELP croît avec le nombre de voisins détectés. À **N=30**, on observe généralement :

- Plus de probes/réponses ELP ;
- Plus d'OGM reçus/retransmis ;
- Concurrence accrue sur le médium partagé.

### 7.2 Impact sur le débit

Le débit utile (`iperf3`) peut diminuer car :

- Le trafic de contrôle occupe la bande passante ;
- Les collisions / files d'attente sur le bridge augmentent ;
- Le CPU des conteneurs traite plus de trames BATMAN.

### 7.3 Impact sur la latence

La latence ICMP inclut :

- Traitement BATMAN-Adv ;
- Encapsulation / décapsulation ;
- File d'attente derrière le trafic de contrôle.

### 7.4 Limites de l'environnement virtuel

- Bridge Docker ≠ radio WiFi (pas de perte/air, pas de half-duplex réaliste) ;
- Tous les nœuds sont à 1 saut L2 (pas de topologie multi-sauts radio) ;
- Les résultats sont **comparatifs** (tendances), pas absolus pour un déploiement terrain.

---

## 8. Améliorations et travail futur

### 8.1 Pistes d'optimisation

| Piste | Description |
|-------|-------------|
| **Ajuster `elp_interval`** | Réduire la fréquence ELP sur réseaux denses |
| **Limiter les hardifs** | N'attacher que les interfaces utiles |
| **Segmentation** | Diviser le mesh en domaines (réduire densité locale) |
| **OGM aggregation** | Exploiter les optimisations batman-adv récentes |

### 8.2 Travaux futurs

1. **Topologies multi-sauts** : chaîne ou grille de conteneurs avec isolation L2 ;
2. **Comparaison ELP ON/OFF** : si le noyau le permet, mesurer avec intervalle ELP extrême ;
3. **Mobilité** : coupler `mesh_random_walk.sh` avec mesures de convergence ;
4. **Dégradation radio** : `tc netem` (perte, délai) à densité fixe ;
5. **Validation terrain** : reproduire sur hardware WiFi (Raspberry Pi / glinet).

### 8.3 Recommandations pratiques

- Réseaux **faible densité** (< 15 nœuds) : paramètres par défaut suffisants ;
- Réseaux **haute densité** : augmenter `elp_interval`, monitorer le trafic `0x4305` ;
- Toujours corréler métriques utilisateur (débit/latence) avec trafic de contrôle.

---

## 9. Conclusion

Ce projet fournit un **environnement reproductible** pour étudier l'impact d'ELP et du plan de contrôle BATMAN-Adv. La méthodologie par **niveaux de densité** permet de quantifier la surcharge et son effet sur débit et latence. Les scripts automatisent la collecte ; le rapport final complète avec graphiques et analyse critique des limites.

---

## 10. Références

1. Open Mesh Project — BATMAN-Adv Wiki : https://www.open-mesh.org/projects/batman-adv/wiki
2. Kernel documentation — `Documentation/networking/batman-adv.txt`
3. Neumann, A. et al. — *BATMAN Advanced (BATMAN-Adv) Characterization*
4. Clausen, T. & Jacquet, C. — *Optimized Link State Routing Protocol (OLSR)*
5. RFC 3561 — *Ad hoc On-Demand Distance Vector (AODV)*

---

## Annexe A — Arborescence des scripts

```
scripts/
  lab_config.sh             # Topologie partagée (30 nœuds, subnet)
  start_lab.sh              # Démarre le labo
  setup_batman.sh           # Configure bat0 sur tous les nœuds
  set_mesh_density.sh       # Active node1..nodeN
  elp_density_benchmark.sh  # Campagne densité → métriques
  summarize_elp_benchmark.sh# Résumé CSV
  run_elp_study.sh          # Orchestration complète
  mesh_fault.sh             # Fautes L2 / netem
  mesh_random_walk.sh       # Churn aléatoire
```

## Annexe B — Checklist rapport final

- [ ] État de l'art (section 2)
- [ ] Schéma BATMAN-Adv (section 3)
- [ ] Description environnement (section 4)
- [ ] Tableaux de mesures remplis (section 6)
- [ ] Graphiques densité / métriques
- [ ] Discussion limites (section 7.4)
- [ ] Pistes d'amélioration (section 8)
