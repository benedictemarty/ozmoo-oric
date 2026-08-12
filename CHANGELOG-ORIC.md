# CHANGELOG — Portage Ozmoo ORIC (branche `oric-port`)

Format inspiré de Keep a Changelog. Le portage suit une logique agile
(incréments verticaux, tests et documentation tenus à jour à chaque commit).

## [0.12.0] - 2026-08-12 — EPIC 3/5 : hang d'init CORRIGÉ, l'init s'exécute en entier
### Majeur
- **Hang d'init v0.11.0 CORRIGÉ.** `kernal_getchar` et `kernal_delay_1ms`, jusque-là
  placeholders `$0000` dans `constants-oric.asm`, sont désormais de vraies routines Oric
  (`keyboard-oric.asm`) : `kernal_getchar` → `read_key` (GETIN non bloquant, A=ASCII/0) ;
  `kernal_delay_1ms` → boucle calibrée ~1 ms **préservant X/Y** (requis par `wait_yx_ms`).
- **`keyboard-oric.asm` intégré au build moteur** (sourcé sous `TARGET_ORIC`) et
  `kbd_init` appelé à `program_start` (init matrice clavier). Fin de l'isolement standalone
  du module clavier (EPIC 3 « branché »).
- **L'init Ozmoo s'exécute intégralement sur Oric** : splash (attente ~15 s, poll clavier
  réel) → `deletable_init` → `parse_object_table`. Prouvé par marqueurs `123` à l'écran
  (test E2E). Les builds VMEM (12032 o) et non-VMEM (11008 o) assemblent exit 0.

### Tests
- `test-oric/init_e2e.sh` (ex-`trace_hang.sh`) : test E2E d'init avec assertion `123`
  (30 M cycles pour dépasser le splash). **PASS.**
- `kbd_read.asm` re-validé (touche `1` → `read_key` renvoie `$31`). **PASS.**

### Diagnostic (outillage émulateur) — méthode ayant localisé la cause
- **Cause racine du blocage v0.11.0 confirmée** : `splash_screen` (appelé en L946
  de `ozmoo.asm`, `SPLASHWAIT=15`) exécute `jsr kernal_getchar` (L91 de
  `splashscreen.asm`), or `kernal_getchar = $0000` dans `constants-oric.asm:168`
  (placeholder `>>> PORT TODO`). Le `jsr $0000` déraille l'exécution → atterrit dans
  le scanner de chaîne de la ROM BASIC (`$D5C5-$D5D0`, recherche du `"` #$22) avec
  `$DE/$DF=$AE03` (zone `$55`, jamais `"` ni `0`) → **boucle infinie**.
- Second placeholder sur le même chemin : `wait_a_jiffy` (L97 splash) → `kernal_delay_1ms`
  = `$0000` (`constants-oric.asm:134`). À corriger conjointement.
- Méthode : `--profile` (adresse chaude `$D5C5` = 9,7 % × plusieurs = la boucle),
  `--dump-ram-at` (ZP `$DE/$DF`, `$24/$25=$2222`, pile), `--vicelabels`/`--symbols`
  (noms Ozmoo). Remplace la bissection par marqueurs écran, jusque-là bloquée.

### Infra
- Script de repro+diagnostic `test-oric/init_e2e.sh` : build voie B non-VMEM avec
  labels VICE, image `$500`+story (`story_start` lu dynamiquement dans le `.lab`),
  run headless ROM+`-f`+`CLOAD`, profil + dump RAM + assertion `123`.

## [0.11.0] - 2026-08-12 — EPIC 5 : l'interpréteur porté S'EXÉCUTE sur Oric
### Majeur
- **Build non-VMEM Oric** (sans `-DVMEM`) assemble (exit 0). Image combinée
  interpréteur ($500..$2eff) + story `.z3` (à `story_start=$2f00`), chargée via tape.
- **Preuve d'exécution** : `program_start` ($500) est atteint et exécuté sur Oric
  (marqueur 'Z' + halt via drapeau `ORIC_HALT_AT_START`). L'init efface l'écran (`s_init`).
  → Moteur + écran + (assemblage) tournent réellement sur la machine.

### En cours (debug)
- Blocage dans le code d'init, entre `deletable_screen_init_1` (cls OK) et
  `deletable_init` (~L1058), indépendant du story. Bisection par `ORIC_DEBUG_INIT`.
- Bug identifié : `s_printchar` ne gère pas les codes de contrôle PETSCII
  (147 = clear screen) — à traiter dans `screenkernal-oric`.

### Infra
- Drapeaux debug guardés `ORIC_HALT_AT_START` / `ORIC_DEBUG_INIT` (OFF en build normal ;
  builds VMEM et non-VMEM vérifiés exit 0).

### Reste
- Localiser/corriger le blocage d'init → atteindre l'exécution Z-code (1er texte de jeu).
- Gérer les codes de contrôle dans `s_printchar`. Puis voie A (constructeur de disque).

## [0.10.0] - 2026-08-12 — EPIC 5 (kickoff) : plan boot loader / première exécution
### Analysé
- En VMEM, `disk_info` est rempli au **boot** depuis une **piste de config**
  (`CONF_TRK=1`) que `make.rb` écrit avec la géométrie du story-file. Structure
  `disk_info` décodée (interleave, nb disques, par disque : device/blocs/pistes/
  secteurs par piste).
- Deux voies documentées vers la 1re exécution :
  - **A (VMEM + constructeur de disque Oric)** : répliquer le layout make.rb (blocs
    story + piste config) sur MFM Oric, boot loader lit la config → `program_start`.
  - **B (non-VMEM + petit story embarqué)** : voie courte pour prouver « le moteur
    tourne » (Z-code exécuté + `s_printchar`), sans constructeur de disque.
- Recommandation : B d'abord (preuve d'exécution), puis A (vrais jeux paginés).

### Reste
- Choisir un story de test minimal ; tenter build non-VMEM Oric + embarquement (B) ;
  porter le constructeur de disque + piste config (A).

## [0.9.0] - 2026-08-12 — EPIC 3 : lecture clavier (scan matrice) validée
### Ajouté
- **`asm/keyboard-oric.asm`** : scan de la matrice clavier Oric + `read_key` (→ ASCII).
  Colonne via VIA ORB `$0300` b0-2, ligne via masque PSG R14, détection PB3 ;
  handshake PSG par PCR `$030C` ($EE/$EC/$CC) ; R7 bit6=1 (port A entrée).
  `kay_write` préserve A/X/Y. Table `(col*8+row)→ASCII` (partielle) intégrée.
- `test-oric/kbd_scan.asm` (scan brut → col/row) et `test-oric/kbd_read.asm`
  (`read_key` → ASCII).

### Validé (sur Phosphoric, via `--type-keys`)
- Scan brut : `'1'` détecté en col0/row5 → "K05" (conforme à `keyboard.c`).
- `read_key` : `'1'`→`'1'`, `'0'`→`'0'`, espace→espace.

### Diagnostic
- Bug initial : `ay_write` écrasait Y (compteur de ligne). Corrigé : sauvegarde
  A/X/Y (même discipline registres qu'en EPIC 2).

### Reste EPIC 3
- Compléter la table ASCII (lettres/shift/touches spéciales) ; brancher
  `kernal_readchar`/`getchar` sur `read_key` (+ variante bloquante).

## [0.8.0] - 2026-08-12 — EPIC 4 : lecture disque intégrée au moteur (VMEM)
### Ajouté
- `disk.asm` : lecture Microdisc/WD1793 **inline** sous `!ifdef TARGET_ORIC` au
  point d'entrée `.have_set_device_track_sector` (là où `readblock` saute avec
  `.track`/`.sector` remplis). Copie `readblocks_mempos` → `zp_mempos` (pointeur ZP)
  puis lit 256 octets. Le corps C64 (canaux KERNAL/U1) est basculé en branche `else`.

### Résultat
- **Le moteur complet assemble (ACME exit 0)** avec le chemin réel
  VMEM → `readblock` → lecture Microdisc. La pagination est branchée sur le disque.
- La logique de lecture est identique à `disk-oric.asm`, déjà validée en isolation
  (piste0/sect1 + seek piste2/sect3). Les deux copies documentées comme à garder en phase.

### Reste EPIC 4
- `disk_info` (géométrie) + placement story-file ; écriture secteur (save/restore) ;
  **boot loader** (charger interpréteur+jeu depuis disque) → première exécution du moteur.

## [0.7.0] - 2026-08-12 — EPIC 4 : read_track_sector (WD1793) écrit et validé
### Ajouté
- **`asm/disk-oric.asm`** : `read_track_sector` pour le Microdisc WD1793 — LA seule
  routine disque machine-spécifique. Contrat Ozmoo respecté (A=piste, X=secteur,
  Y=device, dest=`readblocks_mempos`). Séquence : contrôle `$0314`, Restore, Seek
  (data reg), Read Sector `$80`, polling BUSY/DRQ, lecture `$0313`.
- `test-oric/read_sector.asm`, `read_sector_seek.asm`, `rts_test.asm` : tests sur
  disque à **contenu connu** (raw→MFM via `dsk_raw2mfm.py`).

### Validé (sur Phosphoric)
- Lecture **piste0/secteur1** : motif connu affiché → PASS.
- **Seek + lecture piste2/secteur3** : motif distinct affiché → PASS.
- `read_track_sector` **paramétré** (registres) : PASS.
- → Le verrou technique majeur d'EPIC 4 (pagination VMEM) est levé : lire un secteur
  arbitraire du disque en RAM fonctionne.

### Méthode
- Disque de test déterministe : image brute side-major avec motif ASCII connu à
  (piste,secteur) → conversion MFM → lecture vérifiée par capture écran.

### Reste EPIC 4
- `disk_info` (géométrie) + placement story-file ; brancher VMEM sur `disk-oric.asm` ;
  écriture secteur (save/restore) ; boot du moteur.

## [0.6.0] - 2026-08-12 — EPIC 4 (kickoff) : analyse contrat disque + socle validé
### Analysé
- **`read_track_sector`** identifiée comme la SEULE routine disque machine-spécifique
  (A=piste, X=secteur, Y=device, dest=`readblocks_mempos`). `readblock`/`readblocks`
  (bloc→piste/secteur via `disk_info`), multi-disque et VMEM sont portables.

### Validé
- **Sedoric DOS V4.0 boote** depuis `.dsk` dans Phosphoric (Microdisc, ~11M cycles).
- Émulateur : WD1793 complet + Sedoric ; disques et outils de build présents.

### Gate identifié
- `sedoric_inject.py` attend un `.dsk` brut ; `SEDO40u.DSK` est en MFM → conversion
  `dsk_raw2mfm.py` à intégrer pour injecter/lancer un ML depuis disque.

### Backlog EPIC 4
- Build `.dsk` (raw↔MFM) + lancer ML ; `read_track_sector` WD1793 ; `disk_info` ;
  brancher VMEM ; écriture secteur (save/restore).

## [0.5.0] - 2026-08-12 — EPIC 2 : couche écran intégrée au moteur Ozmoo
### Ajouté
- `screenkernal-oric.asm` réécrit pour exposer l'**interface réelle d'Ozmoo** :
  `s_init`, `s_printchar` (71 appelants dans le moteur), `s_plot`,
  `s_set_text_colour`, `s_reset_scrolled_lines`, `convert_petscii_to_screencode`,
  `s_erase_line`, + stubs curseur/darkmode et variables d'état écran.
- `test-oric/s_printchar_test.asm` : **test unitaire** appelant `s_init`/`s_printchar`
  comme le moteur — **PASS** ("HELLO VIA S_PRINTCHAR" + "SECOND LINE").
- `ozmoo.asm` : source `screenkernal-oric.asm` au lieu de `screenkernal.asm` pour
  `TARGET_ORIC`.

### Résultat
- **Le moteur complet assemble avec la couche écran Oric** (ACME exit 0) — 9 stubs
  de support (curseur/darkmode/couleur) ajoutés pour satisfaire `screen.asm`/`text.asm`.
- Tests écran PASS : `s_printchar_test` (contrat Ozmoo) et `screenkernal_test` (scroll).
- Harnais `run-test.sh` rendu indépendant du CWD (résolution des `!source`).

### Reste EPIC 2 (non bloquant)
- Attributs série (couleur/inverse bit 7), fenêtres/status-line.
- Preuve « moteur imprime » de bout en bout : dépend du chargement story-file (EPIC 4).

## [0.4.0] - 2026-08-12 — EPIC 2 : primitives écran écrites et testées
### Ajouté
- **`asm/screenkernal-oric.asm`** : couche d'affichage bas-niveau Oric —
  `oric_init`, `oric_cls`, `oric_chrout` (CR + wrap 40 colonnes + scroll),
  `oric_scroll`. **Register-safe** (X/Y préservés).
- `test-oric/screenkernal_test.asm` : test du **scroll** — 30 retours-ligne puis
  "SCROLL OK" ; sa présence en bas d'écran prouve le défilement. **PASS**.

### Corrigé (diagnostic)
- Le bug de curseur de la v0.3.0 n'était **pas** un conflit page-zéro mais un
  **oubli de préservation du registre X** : `setline` écrasait X, utilisé par
  l'appelant comme index de chaîne → relecture en boucle. Corrigé par
  sauvegarde/restauration de X (et Y dans `oric_chrout`). Annotation du test
  historique `screen_cursor.asm` mise à jour.

### Discipline établie
- Toute sous-routine 6502 doit **préserver les registres dont l'appelant dépend**.
  Règle appliquée dans `screenkernal-oric.asm`, à tenir pour tout le portage.

### Reste EPIC 2
- Brancher `oric_chrout` sur le vrai chemin d'impression Ozmoo (`kernal_printchar`).
- Attributs série (couleur/inverse via bit 7) dans le flux.

## [0.3.0] - 2026-08-12 — EPIC 2 (en cours) : pipeline de test + modèle écran validés
### Ajouté
- `test-oric/run-test.sh` : harnais de test bout-en-bout (assemble un .asm avec
  ACME → `bin2tap` → exécute dans Phosphoric headless via CLOAD+fast-load →
  capture `--screenshot-text` → **assertion** sur le contenu écran).
- `test-oric/screen_hello.asm`, `test-oric/screen_twolines.asm` : tests d'affichage
  (adressage absolu) — **PASS** ("HELLO ORIC", puis deux lignes "LIGNE UN/DEUX").
- `test-oric/screen_cursor.asm` : primitive `o_chrout` (curseur+wrap), **WIP**.

### Validé
- **Pipeline complet prouvé** : on peut assembler du 6502, le charger et l'exécuter
  dans l'émulateur Phosphoric, et vérifier l'écran automatiquement.
- **Modèle écran Oric** : base `$BB80`, 40×28, codes ASCII, octets 0-31 = attributs
  série inline, stride ligne = 40, inverse = bit 7. (Confirmé par poke direct + ML.)
- **Méthode de chargement ML** : tape auto-run + `CLOAD""` déclenché par `--type-keys`
  (le `-f` seul n'amorce pas la lecture tape).

### Connu (à corriger)
- `o_chrout` via pointeur page-zéro `$f0-$f3` : conflit avec l'usage ROM Oric
  (curseur système) → sortie corrompue. Correctif : reloger la ZP (carte ZP libre
  Oric à établir) ou code auto-modifiant. Prochaine tâche EPIC 2.

## [0.2.0] - 2026-08-12 — EPIC 1 terminé : le moteur assemble pour l'Oric
### Ajouté
- `build-oric.sh` : script de build ACME dédié (indépendant de make.rb / exomizer
  / vice), génère les fichiers requis (`temp/file-name.asm`, `temp/splashlines.asm`)
  et assemble avec les defines nécessaires (`TARGET_ORIC`, `Z3`, `VMEM`,
  `CACHE_PAGES`, `STACK_PAGES`, `CONF_TRK`, versions).
- Placeholders de portage complétant `constants-oric.asm` (registres écran VIC/TED
  inexistants, jeu complet des routines KERNAL, variables d'état écran, buffers clavier).

### Résultat
- **Assemblage complet : ACME exit 0** → binaire `temp/ozmoo-oric.bin` (12 544 o).
  Le moteur Z-machine assemble pour la cible Oric. Le binaire ne s'exécute pas
  encore (routines I/O = placeholders `>>> PORT`).
- Surface de portage entièrement cartographiée : **43 coutures** documentées,
  regroupées en écran/clavier/disque Sedoric/timer/banking (cf. `docs/PORTING_ORIC.md`).

### Méthode
- Convergence itérative de l'assemblage (3 passes) : 10 → 10 → 4 → 0 symboles indéfinis,
  chaque lot révélant la couche I/O suivante.

## [0.1.0] - 2026-08-12 — EPIC 1 : squelette de cible
### Ajouté
- Branche `oric-port` (identité git bmarty <bmarty@mailo.com>).
- Bloc `TARGET_ORIC` dans `asm/ozmoo.asm` (drapeaux : `NO_COLOUR_MAP`,
  `SUPPORT_REU=0`, `SLOW`) + branche d'inclusion `constants-oric.asm`.
- `asm/constants-oric.asm` : carte machine Oric (écran $BB80, banking overlay
  Microdisc), bloc zero-page du moteur Z, et jalons des points d'entrée
  KERNAL→Oric/Sedoric à implémenter.
- `docs/PORTING_ORIC.md` : architecture, surface de portage, différences
  Oric↔Commodore, backlog (épics 1-6), stratégie de test Phosphoric headless.

### Contexte
- Base : Ozmoo v15.7 (GPLv2), supporte Z-machine v1-5/7/8.
- Banc de test : émulateur Phosphoric (`~/Oric1`, Microdisc WD1793 + Sedoric).
- Verrou go/no-go levé : dynamic memory du datafile HHGG mesurée à 9,5 Ko (tient
  en RAM Oric) ; le moteur VMEM d'Ozmoo pagine les 91 Ko de high memory depuis le disque.

### À suivre (EPIC 1, reste)
- Cible Oric dans `make.rb` / script de build ACME.
- Première passe d'assemblage pour lister les symboles indéfinis (backlog EPIC 2+).
