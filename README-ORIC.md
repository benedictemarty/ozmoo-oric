# Ozmoo — Portage ORIC-1 / Atmos

Portage de l'interpréteur Z-machine [**Ozmoo**](https://github.com/johanberntsson/ozmoo)
(Johan Berntsson & Fredrik Ramsberg, GPLv2) vers l'**ORIC-1 / Atmos** (6502, contrôleur
disque **Microdisc** + DOS **Sedoric**).

Objectif : faire tourner des jeux Z-machine **V3 et V5** — y compris de **gros jeux qui
ne tiennent pas en RAM** — grâce à la **mémoire virtuelle** d'Ozmoo (pagination des blocs
du jeu depuis la disquette à la demande).

> Branche de travail : **`oric-port`**. Ce portage réutilise le moteur Z-machine d'Ozmoo
> tel quel ; le travail porte sur la couche d'entrées/sorties `TARGET_ORIC` (écran, clavier,
> disque Microdisc/Sedoric, carte mémoire) et l'outillage de construction de disquettes.

## État — ce qui fonctionne

- ✅ **Moteur Z-machine V3 en VMEM depuis la disquette** — `czech.z3` (testeur de conformité)
  passe **349/0**.
- ✅ **Moteur Z-machine V5 en VMEM depuis la disquette** — `czech.z5` passe **406/0**
  (adresses packées ×4, objets 14 octets / 48 attributs, opcodes V5).
- ✅ **Gros jeu V3 réel jouable** — *The Hitchhiker's Guide to the Galaxy* (V3, **111 Ko**)
  boote, affiche son intro et **répond aux commandes tapées** (parser multi-mots).
- ✅ **Vrai jeu V5 jouable** — *Adventure / Colossal Cave* (PunyInform, **V5, 80 Ko**) boote
  en VMEM, affiche son intro et **répond aux commandes** (`> east` → « Inside Building… »).
  Chaîne V5 interactive complète : `@aread` + écho + tokenisation V5 + parser.
- ✅ **Saisie ligne `@sread` (V3) et `@aread` (V5)** — clavier complet (matrice Oric), écho,
  `RETURN`, effacement (`Backspace`/`Delete`), parsing dictionnaire.
- ✅ **Affichage** — texte, inverse-vidéo (attributs série Oric), ligne de statut V3,
  scroll respectant la fenêtre.

## Architecture du portage

- **Écran** — mode TEXT 40×28 à `$BB80`, ASCII, attributs série (pas de colour-map).
  `asm/screenkernal-oric.asm`.
- **Clavier** — scan de la matrice 8×8 via VIA/PSG, table complète (lettres, RETURN,
  DELETE). `asm/keyboard-oric.asm`.
- **Disque** — lecture secteur **WD1793** (Microdisc) ; la mémoire virtuelle d'Ozmoo
  (`readblock`/`vmem`) pagine les blocs statiques du jeu depuis la disquette.
  `asm/disk-oric.asm` + intégration dans `asm/disk.asm`.
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
#    -DZ3 ou -DZ5, -DVMEM, story sur pistes hautes (-DCONF_TRK=15)
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
- `kbd_table_test.sh` — table clavier (lettres, chiffres, RETURN=13, DEL=8).
- `run-test.sh`, `init_e2e.sh`, `czech_test.sh` — écran/clavier/disque, init, conformité tape.

> Les fichiers de jeux **commerciaux** ne sont pas versionnés (attendus hors du dépôt).

## Documentation

- **[CHANGELOG-ORIC.md](CHANGELOG-ORIC.md)** — journal détaillé, incrément par incrément.
- **[docs/PORTING_ORIC.md](docs/PORTING_ORIC.md)** — plan de portage, EPICs, notes techniques.

## Limitations connues / à venir

- Banking `$C000-$FFFF` (RAM overlay sous ROM) non encore implémenté → plus le jeu est
  gros, plus la pagination disque est fréquente (jouable mais plus lent).
- Story multi-faces : `read_track_sector` force la face 0 (à étendre pour les jeux
  dépassant une face).

## Licence & crédits

GPLv2, comme le projet Ozmoo d'origine. Le moteur Z-machine, l'abstraction `TARGET_*` et
l'essentiel du code sont l'œuvre de **Johan Berntsson** et **Fredrik Ramsberg**
(dépôt amont : <https://github.com/johanberntsson/ozmoo>). Ce portage ajoute la cible
ORIC (`TARGET_ORIC`) et son outillage.
