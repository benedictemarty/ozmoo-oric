# Ozmoo — Portage ORIC-1 / Atmos

Portage de l'interpréteur Z-machine [**Ozmoo**](https://github.com/johanberntsson/ozmoo)
(Johan Berntsson & Fredrik Ramsberg, GPLv2) vers l'**ORIC-1 / Atmos** (6502, contrôleur
disque **Microdisc** + DOS **Sedoric**).

Objectif : faire tourner des jeux Z-machine **V3, V5 et V8** — y compris de **gros jeux qui
ne tiennent pas en RAM** (jusqu'à **512 Ko** répartis sur les deux faces de la disquette) —
grâce à la **mémoire virtuelle** d'Ozmoo (pagination des blocs du jeu depuis la disquette à
la demande).

> Branche de travail : **`oric-port`**. Ce portage réutilise le moteur Z-machine d'Ozmoo
> tel quel ; le travail porte sur la couche d'entrées/sorties `TARGET_ORIC` (écran, clavier,
> disque Microdisc/Sedoric, carte mémoire) et l'outillage de construction de disquettes.

## Rapport avec le projet amont (fork autonome)

Ce portage est maintenu comme un **fork autonome et public** :
<https://github.com/benedictemarty/ozmoo-oric>.

Une proposition d'intégration a été soumise à l'amont
([johanberntsson/ozmoo#84](https://github.com/johanberntsson/ozmoo/issues/84), 2026-09-07).
L'auteur d'Ozmoo a jugé le code **propre et bien isolé** (tout l'Oric est encapsulé derrière
`!if TARGET_ORIC { ... }`, sans impact sur les cibles existantes) mais a préféré **ne pas
fusionner** la cible Oric — coût de maintenance (émulateur + tests de non-régression à chaque
release) et diffusion très restreinte de l'Oric hors de France/UK — tout en proposant d'ajouter
un lien vers ce dépôt depuis sa documentation.

En conséquence, le développement se poursuit ici, avec la **branche amont synchronisée**
(`upstream = johanberntsson/ozmoo`) pour continuer à bénéficier des évolutions du moteur
Z-machine.

## État — ce qui fonctionne

- ✅ **Moteur Z-machine V3 en VMEM depuis la disquette** — `czech.z3` (testeur de conformité)
  passe **349/0**.
- ✅ **Moteur Z-machine V5 en VMEM depuis la disquette** — `czech.z5` passe **406/0**
  (adresses packées ×4, objets 14 octets / 48 attributs, opcodes V5).
- ✅ **Story sur 2 faces + V8 jusqu'à 512 Ko** — `read_track_sector` bascule sur la face 1
  au-delà d'une face (placement de piste linéaire), et le moteur assemble/exécute en **V8**
  (`-DZ8`). *Jigsaw* (V8, 298 Ko) et *Heroine* (V8, 511 Ko) booten et se jouent.
- ✅ **Gros jeu V3 réel jouable** — *The Hitchhiker's Guide to the Galaxy* (V3, **111 Ko**)
  boote, affiche son intro et **répond aux commandes tapées** (parser multi-mots).
- ✅ **Jeu V5 réel jouable** — le test automatisé utilise *dragontroll* (V5) ; *Adventure /
  Colossal Cave* (PunyInform, **V5, 80 Ko**) a été **validé manuellement** (`> east` →
  « Inside Building… »). Chaîne V5 interactive complète : `@aread` + écho + tokenisation V5 + parser.
- ✅ **Saisie ligne `@sread` (V3) et `@aread` (V5)** — clavier complet (matrice Oric), écho,
  **curseur de saisie** visible, `RETURN`, effacement (`Backspace`/`Delete`), parsing dictionnaire.
- ✅ **Sauvegarde / restauration `@save` / `@restore`** — écriture secteur WD1793, slot unique
  en secteurs bruts sur les pistes hautes (`asm/disk.asm`, `write_track_sector`).
- ✅ **Affichage** — texte, inverse-vidéo (attributs série Oric), ligne de statut V3,
  scroll respectant la fenêtre, prompt de pagination `[MORE]` lisible (`-ESPACE-` en inverse).
- ✅ **Accents français** (opt-in `-DORIC_ACCENTS`) — 19 glyphes accentués construits dans le
  charset RAM (`asm/accents-oric.asm`) pour la fiction interactive francophone.
- ✅ **Couleur V5 `@set_colour`** (opt-in `-DORIC_COLOUR`) — encre de premier plan via les
  attributs série, sans décalage du texte.
- ✅ **Saisie temporisée et son** — horloge VIA Timer 1 (`@read` temporisé) et bip
  `@sound_effect` via l'AY-3-8912.

## Architecture du portage

- **Écran** — mode TEXT 40×28 à `$BB80`, ASCII, attributs série (pas de colour-map).
  `asm/screenkernal-oric.asm`.
- **Clavier / temps / son** — scan de la matrice 8×8 via VIA/PSG, table complète (lettres,
  RETURN, DELETE) ; horloge VIA Timer 1 (60 Hz) pour la saisie temporisée ; bip AY-3-8912.
  `asm/keyboard-oric.asm`.
- **Disque** — lecture **et écriture** secteur **WD1793** (Microdisc) ; la mémoire virtuelle
  d'Ozmoo (`readblock`/`vmem`) pagine les blocs statiques du jeu depuis la disquette ;
  `read_track_sector` gère les 2 faces (seuil `TRACKS_PER_SIDE`) ; `@save`/`@restore` en
  secteurs bruts. `asm/disk-oric.asm` + intégration dans `asm/disk.asm`.
- **Accents FR** (opt-in) — construction de glyphes accentués dans le charset RAM.
  `asm/accents-oric.asm`.
- **Carte mémoire / boot** — `asm/constants-oric.asm`, cible `TARGET_ORIC` dans
  `asm/ozmoo.asm`. Boot via un fichier **AUTO Sedoric** (interpréteur + mémoire dynamique) ;
  la story est placée en secteurs bruts sur les pistes libres.
- **Construction de disquette** — `tools/build_game_disk.py` (équivalent Oric de `make.rb`) :
  master Sedoric → placement story/config → injection de l'interpréteur AUTO → image MFM.

## Construire et lancer

Prérequis : assembleur **ACME**, **Python 3**, l'émulateur **Phosphoric** (`oric1-emu`) et
un master Sedoric bootable.

```sh
# 1) Interpréteur VMEM (version détectée depuis l'en-tête de la story) :
#    -DZ3 / -DZ5 / -DZ8 (+ options -DORIC_ACCENTS, -DORIC_COLOUR, -DORIC_BANKING),
#    -DVMEM, story sur pistes hautes (-DCONF_TRK=15)
acme --setpc 0x0500 -DTARGET_ORIC=1 -DZ3=1 -DVMEM=1 \
     -DCACHE_PAGES=4 -DSTACK_PAGES=4 -DCONF_TRK=15 \
     -DMAJOR_VERSION_NO=0 -DMINOR_VERSION_NO=1 --cpu 6502 \
     -o interp.bin asm/ozmoo.asm

# 2) Disquette de jeu bootable (Sedoric + story/config en secteurs bruts) :
python3 tools/build_game_disk.py MASTER.dsk interp.bin jeu.z3 jeu.dsk NOM game_id 15

# 3) Lancer dans Phosphoric (fenêtre interactive) :
oric1-emu -r basic11b.rom --disk-rom microdis.rom -d jeu.dsk --scale 3
```

Le boot est lent (chargement du fichier AUTO puis pagination) : patienter jusqu'à
l'affichage de l'intro et du prompt `>`.

## Tests

Scripts de non-régression headless dans `test-oric/` (build + émulateur + assertions) :

- `vmem_disk_run.sh <story>` — conformité czech en VMEM disque (V3/V5 auto-détecté).
- `hhgg_play_test.sh` — jouabilité gros jeu V3 (HHGG : intro + réponse du parser + effacement).
- `v5_play_test.sh` — jouabilité jeu V5 (dragontroll : intro + `@aread`/écho + changement de salle).
- `bank_2face_test.sh` / `bank_biggame_test.sh` — story sur 2 faces + gros V8 (bloc face 1 == story).
- `save_test.sh` — `@save`/`@restore` (aller-retour dynmem).
- `accents_test.sh` — glyphes accentués FR (`-DORIC_ACCENTS`).
- `colour_test.sh` — couleur V5 `@set_colour` (`-DORIC_COLOUR`).
- `cursor_test.sh` / `more_test.sh` — curseur de saisie, prompt `[MORE]`.
- `timer_test.sh` / `beep_test.sh` — horloge VIA 60 Hz, bip AY-3-8912.
- `scroll_unbuf_test.sh` — `s_printchar` non-bufferisé + `s_scroll_oric` : long texte scrollé sans chevauchement.
- `kbd_table_test.sh` — table clavier (lettres, chiffres, RETURN=13, DEL=8).
- `run-test.sh`, `init_e2e.sh`, `czech_test.sh` — écran/clavier/disque, init, conformité tape.

> Les fichiers de jeux **commerciaux** ne sont pas versionnés (attendus hors du dépôt).

## Documentation

- **[CHANGELOG-ORIC.md](CHANGELOG-ORIC.md)** — journal détaillé, incrément par incrément.
- **[docs/PORTING_ORIC.md](docs/PORTING_ORIC.md)** — plan de portage, EPICs, notes techniques.

## Limitations connues / à venir

- Banking `$C000-$DFFF` (RAM overlay sous ROM) : **implémenté en flag opt-in expérimental**
  `-DORIC_BANKING` (**OFF par défaut**). Fait passer HHGG de 42 à 59 blocs RAM (~40 % de
  faults disque en moins). Le crash V5 initial a été **corrigé** (v0.36.1, débordement de
  `s_scroll_oric`) → banking désormais data-correct et sans crash (V3 et V5) ; reste OFF par
  défaut le temps de polir l'affichage sous scroll intensif (bug `num_rows`/word-wrap
  pré-existant). Sans banking (défaut), plus le jeu est gros, plus la pagination disque est
  fréquente (jouable mais plus lent).
- Affichage sous scroll/[MORE] intensif : artefacts word-wrap (lignes qui se chevauchent),
  bug `num_rows` pré-existant, non bloquant pour jouer.
- Majuscules accentuées rares (Î Ô Û Ë Ï Ù…) encore stripées (slots de charset épuisés) ;
  la saisie clavier reste en ASCII (les parseurs FR acceptent l'entrée non accentuée).
- V4/V7 : assemblent (`-DZ4`/`-DZ7`) mais non testés à l'exécution faute de jeu libre.

## Licence & crédits

GPLv2, comme le projet Ozmoo d'origine. Le moteur Z-machine, l'abstraction `TARGET_*` et
l'essentiel du code sont l'œuvre de **Johan Berntsson** et **Fredrik Ramsberg**
(dépôt amont : <https://github.com/johanberntsson/ozmoo>). Ce portage ajoute la cible
ORIC (`TARGET_ORIC`) et son outillage.
