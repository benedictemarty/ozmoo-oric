# CHANGELOG — Portage Ozmoo ORIC (branche `oric-port`)

Format inspiré de Keep a Changelog. Le portage suit une logique agile
(incréments verticaux, tests et documentation tenus à jour à chaque commit).

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
