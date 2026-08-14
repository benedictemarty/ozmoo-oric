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
  - ⚠️ **Carte des buffers (leçon v0.29.0)** : les buffers Ozmoo bas (`print_buffer2`
    $0200, `keyboard_buff` $0277, `key_repeat`, `charset_switchable`, `memory_buffer`
    $02a7) NE doivent PAS chevaucher le **`vmap_buffer`** (VMEM). Placé un temps à $0200
    (page $02), il était écrasé par `print_buffer2` à chaque impression → blocs mal
    mappés → z_pc lisait le mauvais code (7 échecs czech). Vmap relogé en **RAM haute
    libre `$B000-$B0CC`** : zone `$A600-$B3FF` (au-dessus des blocs VMEM non-bankés
    `$3E00..$A5FF`, sous le charset Oric `$B400`/`$B800`).

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

### EPIC 5.0 — Boot loader / première exécution *(analyse & plan)*

**Constat clé** : en mode VMEM, `disk_info` (`disk.asm`, buffer `!fill 71` pour Z3)
n'est **pas** figé dans le binaire : il est **rempli au boot** en lisant une
**piste de config** (`CONF_TRK=1`) que `make.rb` écrit avec la géométrie du
story-file. `readblock` s'en sert pour convertir bloc→piste/secteur.

**Structure `disk_info`** (déduite de `disk.asm`) :
- `+0` interleave · `+2` nombre de disques · puis, par disque (index x) :
  `+3` index disque suivant, `+4` device, `+5/+6` blocs, `+7` nb de pistes avec
  entrées, `+8..` par piste : (secteurs sautés/2 sur 2 bits | secteurs utilisés sur 6 bits).

**Deux voies vers la première exécution :**

- **Voie A — VMEM + constructeur de disque Oric (voie réelle, gros jeux).**
  Répliquer la logique de disposition de `make.rb` (classe disque : interleave,
  `track_length`, `reserved_sectors`, `storydata_start/end_track`, écriture de la
  piste de config) pour produire une disquette **MFM Oric** (42 pistes × 17 secteurs)
  contenant : les blocs du story-file + la piste de config. Puis boot loader :
  charger l'interpréteur (tape ou secteur boot) → lire la piste de config dans
  `disk_info` → `jmp program_start`. `read_track_sector` (déjà validé) fait la pagination.

- **Voie B — non-VMEM + petit story embarqué (voie courte, preuve « le moteur tourne »).**
  Construire Ozmoo **sans VMEM** (tout le jeu en RAM, ~≤ 40 Ko sur Oric) avec un
  **story-file minuscule** (ex. un `.z3` de test) embarqué, chargé via tape avec
  l'interpréteur. Évite tout le constructeur de disque. Fait exécuter du Z-code et
  imprimer via `s_printchar` → **prouve que le moteur tourne sur Oric**. À vérifier :
  support non-VMEM générique (README : « C64/Plus4 »), et mécanisme d'embarquement du story.

**Recommandation** : Voie B d'abord (preuve d'exécution rapide, valide moteur+écran+
clavier ensemble), puis Voie A pour les vrais jeux V5 paginés.

**Avancement voie B (preuve d'exécution) :**
- [x] **Build non-VMEM Oric assemble** (sans `-DVMEM`, exit 0). `program_start=$500`,
      `story_start=$2f00` (code padé jusque-là).
- [x] Image combinée = interpréteur (`$500..$2eff`) + story `.z3` (à `$2f00`), chargée
      via tape (CLOAD). Stories de test : `test/czech.z3`, `oztest.z3`, `strictz.z3` (v3).
- [x] **L'interpréteur porté S'EXÉCUTE sur Oric** : `program_start` atteint (prouvé par
      marqueur 'Z' + halt, drapeau `ORIC_HALT_AT_START`). L'init efface l'écran (`s_init`).
- [~] **Blocage** dans le code d'init, entre `deletable_screen_init_1` (cls OK) et
      `deletable_init` (ligne ~1058) — indépendant du story (le marqueur '1' *avant*
      `deletable_init` ne s'affiche pas). Bisection via drapeau `ORIC_DEBUG_INIT`.
- [ ] **Bug identifié** : `lda #147 : jsr s_printchar` (147 = « clear screen » PETSCII)
      non géré par `screenkernal-oric` (l'écrirait comme caractère). À traiter dans
      `s_printchar` (codes de contrôle : 147=cls, etc.).
- [ ] Localiser/corriger le blocage d'init (probable code REU/SID/scrollback mal gardé
      pour Oric, ou routine appelant un placeholder). Puis atteindre l'exécution Z-code.

**Voie A (jeux réels) — plan détaillé et socle vérifié.** La voie B (non-VMEM,
tape) est validée jusqu'au bout : czech PASSE 349/0, interactif. Pour les vrais
jeux V5 (trop gros pour la RAM), il faut la voie A = VMEM + disque. `make.rb` ne
connaît PAS Oric (cibles Commodore, formats D64/D81, exomizer) → vrai portage du
constructeur de disque. Découpage :

1. **Constructeur de disque** *(socle Python fait : `tools/oric_disk.py`)*. Porte
   fidèlement le placement des blocs story (make.rb `add_story_data`) et le mapping
   `bloc → (piste, secteur)` (asm `readblock`). **Test aller-retour : 2092 blocs OK**
   (interleave 0/1/3/5) → la structure `disk_info` produite est celle qu'attend
   l'interpréteur. Format `disk_info` d'un disque (lu par `readblock`) :
   `[taille=11+nbpistes, device, lastblock+1_hi, lastblock+1_lo, nbpistes] + octets/piste + 6 octets nom`
   ; octet/piste = `64*(secteurs_réservés/2) + secteurs_story` (bits 0-5 = secteurs
   utilisés, bits 6-7 = sautés/2). Reste : en-tête config global + écriture image MFM Oric.
2. **Init `disk_info` au boot** depuis la piste config (`CONF_TRK`) → buffer `disk_info`
   (`!fill 71` en Z3). ✅ **Côté constructeur FAIT (v0.23.0)** : `oric_disk.py`
   `build_config_track_bytes()` sérialise la piste config au format lu par le boot
   (`game_id(4) + octet-taille + disk_info complet + vmem_data`), et
   `build_bootable_disk()` l'écrit dans les 2 secteurs réservés de `CONF_TRK`. Testé :
   **chaîne de boot complète simulée** (piste config → `disk_info` reconstruit comme
   `ozmoo.asm` L2255-2274 → `readblock_full` → données == story, 1200 blocs).
   ✅ **Côté interpréteur : le code existe déjà** — `ozmoo.asm` `deletable_init`
   (L2241-2276, `!ifdef VMEM`) lit la piste config via **`read_track_sector`** (déjà
   porté/validé), copie `game_id`, reconstruit `disk_info`, `auto_disk_config`. Reste
   à faire assembler/tourner ce chemin sous `TARGET_ORIC` (définir `config_load_address`
   et `boot_device` pour l'Oric ; vérifier `auto_disk_config`).
3. **Boot loader** : charger l'interpréteur (tape) + init `disk_info` → 1re exécution VMEM.
   ✅ **Chemin boot assemble & analysé (v0.24.0)** : la build VMEM (`build-oric.sh`) sort
   exit 0 (12032 o) ; `config_load_address=$2800` (RAM), `story_start=$3000`. Le code
   `deletable_init` L2241-2276 lit la piste config via `read_track_sector` (porté ;
   device ignoré). **Blocage tranché** : `load_suggested_pages` charge les pages
   **statiques** depuis le disque, mais la **dynmem** (`nonstored_pages`, résidente) est
   chargée à part (boot-file C64). Sur Oric ⇒ **tape = interpréteur + dynmem** ; le reste
   faulte du disque. `oric_disk.py` fournit désormais `story_vmem_layout()`,
   `build_vmem_data()` (suggère tous les blocs statiques), `story_dynmem_prefix()`
   (`<out>.dynmem`). Reste : assembler la tape VMEM (interp + dynmem à `story_start`),
   convertir l'image en MFM (`dsk_raw2mfm.py`), booter tape+disque dans Phosphoric.

✅ **Finding (harnais readblock standalone) — RÉSOLU en Python (v0.22.0)** : `readblock`
ne trouve la bonne piste que si `.blocks_to_go` est réordonné en big-endian par un passage
dans `.next_disk` (réordonnancement `.blocks_to_go_tmp`). Ce passage n'a lieu que si le
bloc n'est PAS sur le 1er disque → **le `disk_info` réel place la story en disque ≥ 1**,
avec une entrée « disque de sauvegarde » (index 0) en tête (cf. make.rb `config_data` init
L3468 + `build_S1` L1682). Structure complète confirmée :
`[interleave, save_slots, ndisks=2]` + save `[8, dev, 0,0, 0, nom(3)]` + story
`[taille, dev, lb+1_hi, lb+1_lo, nbpistes, octets/piste…, nom(6)]` (le nom n'a PAS de
longueur fixe ; le champ « taille » pilote le saut d'une entrée à l'autre).
`tools/oric_disk.py` fournit `build_full_disk_info()` (cette structure) + `readblock_full()`
(port fidèle du `readblock` **multi-disque**, byte-swap inclus). **Test `_full_disk_info_test`
: 4352 blocs — placement ↔ readblock_full coïncident** via la structure à 2 disques (chemin
que le harnais mono-disque ne couvrait pas). Reste à valider le `readblock` **assembleur**
en contexte VMEM réel (au boot loader).

⚠️ **À valider sur Oric** (détails non tranchés côté format) : base de numérotation
des **secteurs** (Sedoric = 1-based ; `readblock` produit du 0-based → +1 probable
dans `read_track_sector`), gestion des **2 faces** (le `read_track_sector` Oric
actuel force side 0). Le socle `read_track_sector` WD1793 est déjà validé isolément.

### EPIC 5 — Amorçage disque : analyse de l'EPROM Microdisc (v0.25.0)

**Objectif** : version **disque-only** (la cassette est abandonnée ; un V5 ne tient pas
en RAM). Décision retenue avec l'utilisateur : **boot « maison »** (disque brut, sans DOS)
plutôt que fichier AUTO Sedoric. L'analyse empirique de l'EPROM (`microdis.rom`) via
Phosphoric (`--trace`, `--dump-ram-at`, `da65`) révèle toutefois un **couplage fort à
Sedoric** :

- **Reset** : l'overlay EPROM ($E000-$FFFF) est visible, BASIC ROM désactivée
  (`microdisc.c` : `diskrom=romdis=true`). Vecteur RESET = **$EB7E**. L'init copie une
  routine disque de `$EEED`→`$0480` et une de `$EF68`→`$BFE0`, prépare la ZP.
- **Lecture d'amorçage** (prouvée par la trace + dump RAM) : l'EPROM lit **piste 0,
  secteur physique 1** dans un buffer à **$C013** (bloc de paramètres à `$C000` :
  `track, sector=1, bufptr=$13,$C0`). Ce secteur **n'est pas du code** : c'est le
  **secteur système Sedoric** (octets d'en-tête + nom « SEDORIC » à `$C033`, géométrie).
- **Validation + chargement** : l'EPROM **parse cet en-tête** (`LDA $C033,x` etc.), puis
  charge le **DOS** en plusieurs étapes — 8 lectures observées sur secteurs 1,1,3,3,2,1,3,3
  (multi-pistes) — avant de lancer Sedoric (écran « SEDORIC V3.0 » atteint à ~2 M cycles).

**Conclusion (importante)** : l'EPROM Microdisc **ne fournit pas de hook générique**
« charge un secteur et saute dedans » ; son amorçage est un **protocole multi-étapes
propre à Sedoric** (secteur système validé → chargement DOS → handoff). Un boot « 100 %
maison sans DOS » implique donc de **reproduire/leurrer ce protocole** (format du secteur
système que l'EPROM valide + séquence de chargement + adresse de saut), ce qui est
nettement plus lourd qu'anticipé. Détails encore **inconnus** (à ne pas inventer) :
la signature exacte validée, la séquence de chargement DOS et l'adresse de handoff final.

**Voie retenue (décision utilisateur)** : **Bootstrap Sedoric minimal**. On injecte
l'interpréteur comme **fichier AUTO** Sedoric (`sedoric_inject.py`, déjà validé) ; Sedoric
n'amorce QUE le chargement de l'interp, qui prend ensuite **tout le contrôle** et lit la
story en **secteurs bruts** via son propre `read_track_sector` (VMEM). Faible risque,
entièrement outillé, compatible vrai matériel. *(L'alternative « boot maison intégral »
— forger un secteur système leurrant le protocole EPROM — est écartée : reverse-engineering
ROM conséquent pour un gain marginal.)*

**Pipeline cible (disque Sedoric + story brute, à construire) :**
1. Partir d'un disque **Sedoric bootable brut** (2×42×17×256).
2. **Fichier AUTO** = interpréteur VMEM (`build-oric.sh`, padé jusqu'à `story_start=$3000`)
   **+ dynmem** (`<story>.dynmem`, chargé à $3000) ; `sedoric_inject.py` load=$500 exec=$500
   + INIST autoexec. Sedoric charge et lance l'interp au boot.
3. **Story en secteurs bruts** (`oric_disk.py`) sur des pistes que Sedoric **ne peut pas
   réallouer** → à **réserver dans le bitmap Sedoric** (comme make.rb réserve dans le BAM
   C64). Éviter la **piste système Sedoric** (piste 20) et les pistes du fichier AUTO.
4. **Piste config** `CONF_TRK` (déjà produite par `oric_disk.py`) sur une piste réservée.
5. Convertir l'image brute → MFM (`dsk_raw2mfm.py`) ; booter (`--disk-rom microdis.rom
   -d img.dsk`) → Sedoric → AUTO interp → **1re exécution VMEM** (story faulte du disque).

✅ **Coexistence résolue (analyse `sedoric_inject.py`/`sedoric_mkbare.py`)** : le layout
Sedoric est **simple à cohabiter** :
- **Piste 20** = piste système Sedoric (sec 1 = secteur système + INIST autoexec ;
  sec 2 = VTOC/bitmap ; sec 4 = directory).
- **Pistes 21+** = zone d'allocation des fichiers : `sedoric_inject.py` alloue **à partir
  de la piste 21, secteur 1**, en montant (saute la piste 20). Le fichier AUTO interpréteur
  (~15 Ko ≈ 4 pistes) occupe donc ≈ pistes 21-24.
- **Pistes 1-19 = LIBRES** → réservées à nos **secteurs bruts** (story + piste config).
  `oric_disk.py` place déjà la story dès la piste 1 → **aucune collision** pour un petit
  jeu (czech = 42 blocs ≈ 3 pistes). L'interp n'accède JAMAIS la story via Sedoric : il
  utilise son propre `read_track_sector` (raw). Le disque étant construit une fois et
  lu seul, pas besoin de marquer les secteurs story dans le bitmap (rien n'écrit après).
- **Gros V5** (~100 Ko) : la story débordera des pistes 1-19 → l'étendre sur pistes 25-41
  + **face 1** (déjà prévu : `read_track_sector` à étendre pour piste>41), en évitant
  20 et la zone interp. Optimisation ultérieure ; sans objet pour la 1re preuve.

**Construction du fichier AUTO (mesuré, build VMEM `--vicelabels`) :** le binaire VMEM
fait **exactement $0500–$33FF** (12032 o) et se termine **pile à `story_start=$3400`**.
Adresses : `program_start=$0500`, `program_end=$2BA9`, `vmem_cache_start=config_load_address=$2C00`,
`stack_start=$3000`, `deletable_init=$3079` (vit **dans la pile** — astuce « deletable »,
écrasée après usage), `story_start=$3400`. Donc **fichier AUTO = interp ($500–$33FF) +
dynmem (`<story>.dynmem`, chargé à $3400)** — sans chevauchement. Pour czech : +2560 o de
dynmem → fichier $500–$3DFF ; les blocs statiques faultent du disque à `$3E00+`
(`vmap_first_ram_page = nonstored_pages + >story_start = $3E`). `sedoric_inject.py` :
load=$500, exec=$500 (=`program_start`).

**Outil `tools/mfm2raw.py` (fait, testé)** : extrait une image MFM_DISK Phosphoric →
RAW side-major (inverse de `dsk_raw2mfm.py`). Round-trip raw→MFM→raw = identité ; testé
sur `sedoric3.dsk`/`SEDO40u.DSK` (re-MFM reboote « SEDORIC V3.0 »).

⚠️ **Géométrie — à trancher pour le builder** : les masters Sedoric fournis
(`sedoric3.dsk`, `SEDO40u.DSK`) sont en **80 pistes/face** (pas 42) et **pleins**
(pistes 1-19 occupées). `oric1-emu --disk-create` produit un blank **42 pistes** (=géométrie
`oric_disk.py`) mais **non bootable** (« insert system disc ») ; `make_bootable_sedoric.sh`
échoue à le rendre bootable (timing calibré 80 pistes). `read_track_sector` **force side 0**
et seek n'importe quelle piste → OK jusqu'à 79 sur face 0.

**Reste à faire (builder disque de jeu Sedoric) — le vrai prochain incrément :** un
`build_game_disk.py` façon make.rb : partir d'un master **bootable** (via `mfm2raw`), lire
le **catalogue/VTOC** pour la carte des secteurs libres, y placer story+config (secteurs
bruts) **et** marquer ces secteurs occupés dans le bitmap, injecter l'interp AUTO
(`sedoric_inject`), régler l'INIST autoexec pour lancer l'interp, reconvertir en MFM. La
marche de catalogue (chaîne directory `t20s4`) doit être robuste (bornes) — première
tentative inline a dérivé sur un descripteur hors borne. Puis **1re exécution VMEM**.

- [x] Faire tourner un jeu **V3** (parité Pinforic) sur Phosphoric — ✅ HHGG (111 Ko) jouable (v0.32.0)
- [x] Faire tourner un jeu **V5** (objectif final) — ✅ advent_punyinform (80 Ko) jouable + test
      `v5_play_test.sh` (dragontroll) (v0.35.0)

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
