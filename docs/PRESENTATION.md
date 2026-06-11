# Guide présentation — résultats du lab

## Lire votre tableau density (exemple)

| density | batman_pps | neighbors | ping (ms) | throughput |
|---------|------------|-----------|-----------|------------|
| 2       | bas        | 1         | ~0.01     | élevé (Docker) |
| 10      | ↑          | ~9        | ~0.02     | élevé      |
| 30      | max        | ~29       | ~0.03     | élevé      |

### Ce qui est **bon** (à montrer en soutenance)

- **batman_pps augmente** avec la densité (2 → 3 nœuds) : plus de voisins = plus de trafic ELP/OGM sur `eth0` (`0x4305`).
- **ping ≈ 0 ms, 0 % perte** : le mesh data-plane fonctionne.
- **throughput élevé (~8 Gbit/s)** : normal sur Docker/macvlan (L2 virtuel sur la même machine), **pas** une radio WiFi.

### Message clé pour le jury

> « Nous quantifions le **coût du plan de contrôle** BATMAN (PPS) quand la densité augmente, sur un MANET simulé à 3 nœuds. »

## Colonnes CSV

| Colonne | Signification |
|---------|-------------|
| `batman_packets` | Paquets `ether proto 0x4305` capturés (ELP + OGM) |
| `batman_pps` | Charge de contrôle par seconde |
| `neighbors` | Voisins directs (`batctl meshif bat0 n`) |
| `originators` | Nœuds connus dans la table de routage (`batctl meshif bat0 o`) |
| `ping_avg_ms` | Latence applicative node1 → node2 |
| `throughput_mbps` | Débit iperf3 node1 → node2 |

## Démo live (5 min)

```bash
./scripts/observe_batman.sh node1 all
./scripts/observe_batman.sh node1 traffic 15
docker exec node1 bash -lc "batctl meshif bat0 ping -c 3 10.0.0.2"
./scripts/fault.sh disconnect node3
./scripts/observe_batman.sh node1 neighbors
./scripts/fault.sh reconnect node3
```

## BATMAN vs autres protocoles (1 slide)

| | BATMAN-Adv | OLSR / AODV |
|---|------------|-------------|
| Couche | L2 (switch virtuel) | L3 (tables IP) |
| Transparence | IP sur `bat0`, apps inchangées | Routage explicite |
| Contrôle | ELP + OGM continu | HELLO / TC ou route request |
| Idéal pour | Mesh communautaire, pont L2 | MANET IP classique |

## Limites à mentionner

- Lab **filaire** (macvlan), pas WiFi : pas d'interférences ni de portée.
- 3 nœuds, topologie plate (tous voisins à 1 saut).
- Débit très haut ≠ performance radio réelle.

## Erreurs bénignes

`Error: Cannot delete qdisc with handle of zero` = nettoyage `tc` sans netem actif (sans impact sur les mesures).
