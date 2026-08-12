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

### EPIC 2 — Sortie écran (afficher du texte) *(en cours)*
- [x] **Pipeline de test bout-en-bout prouvé** : ACME → `bin2tap` → Phosphoric
      (CLOAD + `-f` fast-load, `--type-keys`) → exécution → `--screenshot-text`.
- [x] Harnais réutilisable `test-oric/run-test.sh` (assemble + exécute + assertion).
- [x] **Modèle écran Oric validé** (par poke + ML) : base `$BB80`, 40×28, codes
      **ASCII**, octets 0-31 = **attributs série** inline, stride ligne = 40
      (`$BB80 + row*40`). Inverse vidéo = bit 7 du code caractère.
- [x] Affichage multi-ligne fonctionnel en **adressage absolu** (`test-oric/screen_hello.asm`,
      `screen_twolines.asm` — tests PASS).
- [x] **`asm/screenkernal-oric.asm` : primitives écran écrites et testées** —
      `oric_init`, `oric_cls`, `oric_chrout` (CR + wrap 40 col + scroll),
      `oric_scroll`, register-safe (X/Y préservés). Test scroll **PASS**
      (`test-oric/screenkernal_test.asm` : 30 CR → défilement → "SCROLL OK" en bas).
- [x] **Couche écran au contrat Ozmoo** dans `screenkernal-oric.asm` : `s_init`,
      `s_printchar` (71 appelants), `s_plot`, `s_set_text_colour`,
      `s_reset_scrolled_lines`, `convert_petscii_to_screencode`, `s_erase_line`,
      stubs curseur/darkmode. Variables d'état écran fournies.
- [x] **`s_printchar` testé unitairement** (comme l'appelle le moteur) — PASS
      (`test-oric/s_printchar_test.asm` : "HELLO VIA S_PRINTCHAR" + 2e ligne).
- [x] **Intégré au build** : `ozmoo.asm` source `screenkernal-oric.asm` pour
      `TARGET_ORIC` ; le **moteur complet assemble** (ACME exit 0).
- [ ] Attributs série (couleur/inverse via bit 7) dans le flux d'impression.
- [ ] Fenêtres / status-line (V3) — actuellement fenêtre unique.
- [ ] Preuve « le moteur imprime » de bout en bout : **gâtée par le chargement**
      du story-file (EPIC 4). Le contrat écran, lui, est prouvé isolément.

**Leçon clé (corrigée)** : le bug initial du curseur n'était **pas** un conflit
page-zéro mais un **oubli de préservation de registre** — la sous-routine `setline`
écrasait X, que l'appelant utilisait comme index de chaîne. Discipline à tenir dans
tout le portage : **une sous-routine doit préserver les registres dont l'appelant
dépend** (X/Y sauvegardés/restaurés). Le module `screenkernal-oric.asm` applique
cette règle.

### Méthode de test (mise à jour)
Chargement ML fiable = tape auto-run + déclenchement `CLOAD""` via `--type-keys`
(le `-f` seul n'amorce pas la lecture). Cf. `test-oric/run-test.sh`.

### EPIC 3 — Clavier *(cœur validé)*
- [x] **`asm/keyboard-oric.asm` : scan matrice + `read_key` → ASCII, VALIDÉ.**
      Mécanisme : colonne via VIA ORB `$0300` bits0-2, ligne via masque PSG R14
      (`~(1<<row)`), détection sur PB3 ; handshake PSG via PCR `$030C`
      (latch=$EE, write=$EC, inactif=$CC) ; prérequis PSG R7 bit6=1 (port A entrée).
      Tests PASS : `'1'`→`'1'`, `'0'`→`'0'`, espace→espace (via `--type-keys`).
- [ ] Compléter la table `(col*8+row)→ASCII` (lettres a-z, shift, touches spéciales
      Return/Del/flèches). Table partielle extraite de `keyboard.c` (mécanisme prouvé).
- [ ] Brancher `kernal_readchar`/`kernal_getchar` sur `read_key` (`read_key`=non bloquant ;
      `readchar`/CHRIN = version bloquante avec attente).

### EPIC 4 — Disque Sedoric (le cœur) *(kickoff)*
**Analyse du contrat Ozmoo (fait) :** la seule routine réellement machine-spécifique
est **`read_track_sector`** (`disk.asm`) :
- entrée : `A`=piste, `X`=secteur, `Y`=device, mot en `readblocks_mempos` = adresse dest.
- tout le reste est **portable** : `readblock`/`readblocks` (conversion bloc→piste/secteur
  via la table `disk_info`), multi-disque, et la logique VMEM (`vmem.asm` appelle
  `readblock`/`readblocks`). Save/restore (`do_save`/`do_restore`) réutilise les mêmes primitives + écriture.
- Sur C64, `read_track_sector` passe par le KERNAL/1541 (canaux nommés + U1). Sur Oric,
  à réécrire pour le **WD1793 Microdisc** (registres command/track/sector/data mappés en I/O).

**Socle validé :**
- [x] **Sedoric DOS V4.0 boote** depuis un `.dsk` dans Phosphoric (`--disk-rom microdis.rom
      -d SEDO40u.DSK`), boot ~11M cycles. Le chemin de boot disque fonctionne.
- [x] Émulateur = WD1793 complet (struct `fdc` : command/track/sector/data) + Sedoric.
- [~] **Gate outillage** : `sedoric_inject.py` attend un `.dsk` **brut** ; `SEDO40u.DSK`
      est en **MFM** → utiliser `dsk_raw2mfm.py` (conversion raw↔MFM) pour injecter un ML.

**Registres Microdisc (validés) :** `$0310` cmd/statut (BUSY=$01, DRQ=$02),
`$0311` piste, `$0312` secteur, `$0313` data, `$0314` contrôle (drive b5-6, side b4,
ROMDIS b1, EPROM b7, INTENA b0). Commandes WD1793 : `$00` Restore, `$10` Seek
(cible = registre data), `$80` Read Sector.

**Backlog EPIC 4 :**
- [x] Construction `.dsk` Oric à **contenu connu** (raw side-major → MFM via
      `dsk_raw2mfm.py`) pour tests déterministes.
- [x] **`asm/disk-oric.asm` : `read_track_sector` WD1793 écrit et VALIDÉ** —
      contrat Ozmoo (A=piste, X=secteur, Y=device, dest=`readblocks_mempos`).
      Tests PASS : lecture piste0/secteur1, **et seek+lecture piste2/secteur3**
      (`test-oric/read_sector*.asm`, `rts_test.asm` — motif connu retrouvé à l'écran).
- [x] **VMEM branché sur le disque Oric** : `disk.asm` intègre la lecture WD1793
      inline sous `!ifdef TARGET_ORIC` (au point `.have_set_device_track_sector`,
      lit `.track`/`.sector` → `zp_mempos`). **Moteur complet assemble (ACME exit 0)**
      avec ce chemin VMEM → `readblock` → lecture Microdisc réelle.
- [ ] Setup `disk_info` (géométrie disque Oric) + placement du story-file.
- [ ] Écriture secteur (commande `$A0`) → save / restore d'état.
- [ ] Boot loader : charger l'interpréteur + le story-file depuis disque et
      initialiser `disk_info` → **première exécution réelle du moteur**.

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
