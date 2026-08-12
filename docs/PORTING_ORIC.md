# Portage Ozmoo → ORIC-1 / Atmos

**Objectif** : ajouter une cible `TARGET_ORIC` à Ozmoo pour exécuter des jeux
Z-machine (v1-5/7/8) sur ORIC-1 / Atmos réel, avec pagination disque depuis
Sedoric/Microdisc — afin notamment de faire tourner des jeux **V5** (que
l'interpréteur Oric existant, Pinforic, ne gère pas : il est limité à la V3).

## Écosystème (présent sur la machine)

| Élément | Emplacement | Rôle |
|---|---|---|
| Base Ozmoo (GPLv2, v15.7) | `/home/bmarty/42/ozmoo` (branche `oric-port`) | Code à porter |
| Émulateur **Phosphoric** | `~/Oric1/oric1-emu` | Banc de test (Atmos, Microdisc WD1793 + Sedoric, headless, `--screenshot-text`) |
| Assembleur **ACME** | `acme` (dans le PATH) | Chaîne de build Ozmoo |
| Pinforic (V3, réf.) | `/home/bmarty/42/pinforic` | Interpréteur Oric V3 existant (référence I/O disque/écran) |

## Architecture Ozmoo & surface de portage

Ozmoo = **moteur Z-machine indépendant machine** (réutilisé tel quel) +
**couche I/O spécifique machine** (à écrire pour l'Oric). Les cibles sont
sélectionnées par `!ifdef TARGET_xxx` dans `asm/ozmoo.asm`.

### Ce qui est réutilisé sans modification
Décodeur d'opcodes, pile, table d'objets, dictionnaire, texte ZSCII, **mémoire
virtuelle / pagination disque** (`vmem.asm`) — le mécanisme clé qui permet les
gros jeux V5 sur 8-bit. ~25 000 lignes, dont seulement ~500 spécifiques cible.

### Ce qui doit être écrit pour `TARGET_ORIC`
| Module Commodore | Équivalent Oric à créer | Difficulté |
|---|---|---|
| `constants.asm` | `constants-oric.asm` ✅ *(squelette)* | — |
| `screenkernal.asm` | écran TEXT $BB80 + **attributs série** (pas de colour-map) | Élevée |
| `screen.asm` (VIC/TED) | fenêtres/status-line/scroll Oric ULA | Élevée |
| `disk.asm` (1541/1581) | **Sedoric / Microdisc WD1793** (lecture bloc pour VMEM, save/restore) | Élevée |
| `sound.asm` (SID/TED) | AY-3-8910 (optionnel, non bloquant) | Basse |
| ~15 routines KERNAL | `printchar/readchar/getchar` + `open/close/load/save/...` Oric/Sedoric | Élevée |
| banking `$ff00` | overlay RAM Microdisc `$C000-$FFFF` | Moyenne |
| `make.rb` cible C64 | cible Oric (ACME + outil image `.dsk` + Phosphoric) | Moyenne |

## Différences dures Oric ↔ Commodore
1. **Pas de colour-map** : l'Oric code les attributs (couleur/inverse) *dans* le
   flux de caractères (« série »). Drapeau de port introduit : `NO_COLOUR_MAP`.
2. **Banking** : `$C000-$FFFF` bascule ROM/RAM overlay via le contrôleur
   Microdisc (≈64 Ko exploitables), différent du banking `$01`/`$ff00` Commodore.
3. **Disque** : pas d'API KERNAL ; appels **Sedoric** propres. La vitesse de
   lecture bloc aléatoire conditionne la jouabilité (pagination VMEM).
4. **Saisie temporisée V5** : à câbler sur le timer VIA 6522.

## Verrou go/no-go (levé) ✅
La *dynamic memory* du jeu doit tenir en RAM Oric. Mesuré sur le datafile
HHGG (`hhgg_r59.dat`, en réalité **V3** r59) : **dynamic = 9,5 Ko**, high memory
= 91 Ko (paginable). → tient largement. Un vrai V5 devra être mesuré au cas par
cas (lecture de l'en-tête Z, offset $0E = base static memory).

## Backlog (épics → stories)

### EPIC 1 — Squelette de cible ✅ *(terminé)*
- [x] Branche git `oric-port`, identité bmarty
- [x] Bloc `TARGET_ORIC` dans `ozmoo.asm` + branche d'inclusion constantes
- [x] `constants-oric.asm` (carte machine + zero-page moteur + jalons KERNAL)
- [x] Script de build ACME dédié (`build-oric.sh`, indépendant de make.rb/exomizer/vice)
- [x] **Assemblage complet (ACME exit 0)** → binaire `temp/ozmoo-oric.bin` (12,5 Ko)
- [x] Surface de portage entièrement cartographiée : **43 coutures `>>> PORT`** dans
      `constants-oric.asm` (placeholders documentés). Le moteur Z assemble ; il ne
      *tourne* pas encore (routines I/O = placeholders).

**Bilan seams à implémenter (regroupés) :**
- **Écran/attributs** : `COLOUR_ADDRESS(_DIFF)`, `zp_colourline`, `reg_border/backgroundcolour`,
  `reg_rasterline*`, `s_reverse`, `num_rows`, `is_buffered_window`, `charset_switchable`.
- **Clavier** : `kernal_readchar/getchar`, `keyboard_buff(_len)`, `key_repeat`.
- **Disque Sedoric** : `kernal_setlfs/setnam/open/close/chkin/chkout/clrchn/load/save/readst`,
  `CURRENT_DEVICE`, buffers VMEM (`directory_buffer`, `vmap_buffer_*`).
- **Temps/timer** : `kernal_settime/readtime`, `kernal_delay_1ms` (VIA 6522).
- **Mémoire/banking** : `basic_reset`, `kernal_reset`, `first_banked_memory_page`,
  reloger `print_buffer`/`memory_buffer` hors pile/zones réservées.

### EPIC 2 — Sortie écran (afficher du texte)
- [ ] `screenkernal-oric.asm` : `printchar`, gestion curseur, scroll, attributs série
- [ ] "Hello, Oric" via le chemin d'impression Ozmoo, capturé par `--screenshot-text`

### EPIC 3 — Clavier
- [ ] `readchar`/`getchar` via lecture clavier Oric (VIA/AY colonnes)

### EPIC 4 — Disque Sedoric (le cœur)
- [ ] Lecture bloc pour VMEM (pagination high memory)
- [ ] Chargement du story-file / boot
- [ ] Save / restore d'état

### EPIC 5 — Intégration & jeu
- [ ] Image `.dsk` Sedoric bootable contenant interpréteur + jeu
- [ ] Faire tourner un jeu **V3** (parité Pinforic) sur Phosphoric
- [ ] Faire tourner un jeu **V5** (objectif final)

### EPIC 6 — Qualité (transverse, à chaque incrément)
- [ ] Tests d'assemblage automatisés (build Oric ne régresse pas)
- [ ] Tests d'exécution headless Phosphoric (comparaison de captures écran texte)
- [ ] CHANGELOG + docs tenus à jour, commits atomiques versionnés

## Stratégie de test (Phosphoric, headless)
```bash
~/Oric1/oric1-emu -r ~/Oric1/roms/basic11b.rom \
  --disk-rom ~/Oric1/roms/microdis.rom -d jeu.dsk \
  -n --cycles 5000000 --screenshot-text out.txt
```
Assertions sur `out.txt` (contenu de l'écran $BB80) → tests d'exécution reproductibles.
