# CHANGELOG — Portage Ozmoo ORIC (branche `oric-port`)

Format inspiré de Keep a Changelog. Le portage suit une logique agile
(incréments verticaux, tests et documentation tenus à jour à chaque commit).

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
