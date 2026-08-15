# CHANGELOG — Portage Ozmoo ORIC (branche `oric-port`)

Format inspiré de Keep a Changelog. Le portage suit une logique agile
(incréments verticaux, tests et documentation tenus à jour à chaque commit).

## [0.36.4] - 2026-08-15 — Debug banking V5 : la corruption `$C300` DIRECTEMENT ROOT-CAUSÉE du `[Not supported]` ; writer pas encore isolé
### Contexte
Reprise du bug banking V5 (advent, `-DORIC_BANKING`) : `[Not supported]` imprimé,
corruption du bloc 62 (page `$C2-$C3`) soupçonnée en v0.36.2 sans mécanisme établi.
Repro : `-DORIC_BANKING -DZ5 -DVMEM -DCONF_TRK=15` + `build_game_disk.py … advent_punyinform.z5`.
### Hypothèses RÉFUTÉES (chacune par un test)
- **Lecture disque en zone banked** : nouveau harnais isolé `test-oric/bank_readboundary.asm`
  (lit un bloc 512 o dans `$C200/$C300` via `read_track_sector`, disque à motif non-nul
  `byte[i]=(i+1)&$FF`). Résultat **propre** : `$C300` = `01 02 … 18`, frontière `$C2FF→$C300`
  intacte, contrôle `$6000` identique. → **`read_track_sector` ne perd PAS d'octets** à la
  frontière de page en zone banked.
- **Écriture hors-dynmem (`write_next_byte`)** : `-DCHECK_ERRORS` en banking lève
  `FATAL ERROR: 8` = `ERROR_OPCODE_NOT_IMPLEMENTED`, **PAS** `13` (`ERROR_WRITE_ABOVE_DYNMEM`).
  De plus `story_start=$3A00`, dynmem = `$3A00-$71FF` → **n'atteint jamais `$C300`**.
- **Éviction/mauvais mapping vmap** : l'entrée vmap 34 (page `$C2`) garde `vmap_z_l=$3E`
  **stable** (60M→218M), seuls les bits d'âge de `vmap_z_h` changent → le vmap **croit le
  bloc valide** là où la RAM est écrasée.
### Établi (vérifié, aucune supposition)
- **C'est un ÉCRASEMENT, pas une donnée disque erronée** : `$C300` contient les **bonnes
  données story à 60M** (`01 7f ff 03 c9 8f …`, = story offset `$7C00`+256, 0 zéro en tête)
  puis, entre ~60M et ~80M, **exactement ses 37 premiers octets passent à `$00`** (page 1
  `$C200` et la fin `$C325+` restent intactes ; événement unique).
- **La corruption CAUSE directement le mauvais opcode** : au halt `CHECK_ERRORS`,
  `z_pc_mempointer = $C307` → l'interpréteur **exécute du code depuis la page corrompue**
  (offset +7, dans les 37 octets zérotés) → lit un octet nul → opcode invalide → `[Not supported]`.
  ⇒ **un seul bug** (la note v0.36.2 « le flux a divergé ailleurs, `$C300` incident » est
  corrigée : `$C300` EST sur le chemin z_pc et sa corruption est la cause).
- **`CHECK_ERRORS` = repro déterministe** (halt sur l'opcode fautif) bien plus exploitable
  que le `[Not supported]` non-fatal qui défile.
### Chasse au *writer* — fortement resserrée (cause exacte encore non capturée)
- **Fenêtre pincée à `73,66M–73,69M`** (repro déterministe : clés à 40M+70M ; l'écrasement
  survient ~3,6M cycles après la touche qui dismisse un `[MORE]` à 70M).
- **Le zeroing est PROGRESSIF** : `0 → 20 (73,67M) → 37 (73,69M)` = **plusieurs events**,
  pas un memset unique.
- **Réfuté aussi** (cette passe) : (d) **débordement de pile z** — `stack_ptr=$3624`, pile
  `$3600-$39FF` (`stack_start=$3600`, `stack_size=$0400`), pas `$C300` ; les `STA ($7A),Y`
  vus dans la trace sont l'init normale des locals de `stack_call_routine` ; (e) **chargement
  disque frais** — aucun `readblock` (`$10xx`) dans la fenêtre, `readblocks_mempos=$D200`
  (≠`$C200`) ; (f) **copie de page entière** — seuls 37 octets changent (pas 256) ;
  (g) **memset contigu** — rafale max de 6 stores-zéro consécutifs.
- **Limite de méthode atteinte** : les stores fautifs sont **indirects** (`STA ($zp),Y`),
  la trace CPU ne résout pas la cible et le snapshot ZP ne la reconstitue pas de façon
  fiable ; l'émulateur headless n'a **pas de watchpoint en écriture** (`-b`=PC fait hang).
- **OUTIL DÉCISIF RECOMMANDÉ** : ajouter un **watchpoint écriture sur `$C300`** à
  l'émulateur Phosphoric (source dans `~/Oric1/src`) — loggerait `PC + cycle` du `STA`
  fautif en un seul run. C'est la voie propre vs la trace-ring (rendements décroissants).
**Banking toujours OFF par défaut** ; non-régression build défaut inchangée (czech 349/0,
406/0, advent/HHGG/dragontroll jouables).

## [0.36.3] - 2026-08-15 — Preuve empirique : `$E000-$FFFF` est de la RAM sous `$0314=$80` (banking 16 Ko possible)
### Découverte (issue du portage Civilization Oric)
Le projet Civilization/Oric a démontré que le **banc haut `$E000-$FFFF` (8 Ko)** du Microdisc
devient de la RAM dès que le bit 7 (EPROM) de `$0314` = 1, à condition de désactiver les IRQ
(vecteurs `$FFFA-$FFFF` perdus). Or **Ozmoo réunit déjà ces deux conditions** : `read_track_sector`
écrit `$0314=$80` (bit 7 = 1) **et** le moteur tourne sous **SEI**. Le commentaire
`constants-oric.asm` affirmait pourtant « `$E000-$FFFF` reste EPROM/Sedoric » — **affirmation
non vérifiée et probablement fausse**.
### Ce qui a été fait
- **Poke-test empirique `test-oric/bank_e000.asm` + `bank_e000.sh`** : sous `$0314=$80`,
  écrit 2 motifs distincts (`$5A` puis `$A5`) en `$E000`, `$F000`, `$FFF0` et relit
  (RAM si les 2 tiennent). Contrôle `$C000` (RAM déjà prouvée).
  - **Positif** (Microdisc + boot Sedoric SEDO40u, condition fidèle au runtime) :
    `E000=R  F000=R  FFF0=R  C000=R` → **tout est RAM**. **PASS.**
  - **Contrôle négatif** (BASIC nu, sans Microdisc, `$C000-$FFFF` = ROM BASIC) :
    `E000=O  F000=O  FFF0=O  C000=O` → le test discrimine bien RAM/ROM.
- **Commentaire `constants-oric.asm` corrigé** : `$E000-$FFFF` est de la RAM sous `$0314=$80`
  (16 Ko d'overlay potentiels), l'ancienne mention « reste EPROM/Sedoric » supprimée.
### Portée / suite
- **Aucun changement de comportement** : `first_banked_memory_page` et les bornes VMEM sont
  inchangés ; le banking exploite toujours seulement `$C000-$DFFF` (8 Ko). C'est une
  **preuve + correction de doc**, pas une extension.
- **Piste d'optimisation ouverte** : étendre le banking à **16 Ko** (`$C000-$FFFF`)
  ≈ doublerait les blocs VMEM résidents (moins de faults disque pour les gros V5). À faire
  **après** stabilisation du banking 8 Ko (bug d'exécution V5 encore ouvert, cf. 0.36.2) et
  en relogeant le vmap sous `$E000`.

## [0.36.2] - 2026-08-14 — Investigation garble banking : le path unbuffered+scroll est PROPRE ; le vrai coupable est ailleurs
### Ce qui a été établi
Investigation de l'artefact d'affichage « Did you know...s this edition?e fol » observé en
mode banking (`-DORIC_BANKING`) sur *advent_punyinform* :
- **Build par défaut : RIEN à corriger.** advent V5 joué sur de nombreux tours = affichage
  **parfaitement propre** (status-line, word-wrap des longues descriptions, déplacements,
  réponses parser). HHGG intro propre. Le bug word-wrap/num_rows historique est **résolu**
  depuis v0.34.0 (la note qui le disait ouvert était périmée).
- **Le path `s_printchar` non-bufferisé + `s_scroll_oric` est PROPRE.** Nouveau harnais
  isolé **`test-oric/scroll_unbuf.asm`** (+ `scroll_unbuf_test.sh`) : une longue chaîne
  (110 chars sans CR) imprimée caractère par caractère sur la dernière ligne hard-wrappe à
  la colonne 40 et scrolle **sans chevauchement** (3 lignes exactes). **PASS.** Donc le
  garble n'est **pas** un bug unbuffered+scroll.
- **Le vrai coupable (banking) est un bug d'exécution résiduel, distinct du scroll.** En
  banking, advent exécute `z_ins_not_supported` → imprime **`[Not supported]`** (jamais vu
  en défaut) **alors que le vmap est vérifié PROPRE** (0 entrée hors-story, pas de corruption).
  Un mauvais opcode est donc décodé/exécuté → un read/exec-path banking renvoie de mauvais
  octets pour certains accès sans corrompre le vmap. `inc_z_pc_page`/`set_z_pc` (EOR#1
  intra-bloc) et les 3 sites de skip ont été relus cohérents ; la cause exacte reste à
  isoler (breakpoint sur `z_ins_not_supported` fait hang l'émulateur headless → à instrumenter
  autrement). **Chantier banking dédié**, banking reste OFF par défaut.
### Tests
- **Nouveau** `test-oric/scroll_unbuf_test.sh` (unbuffered + s_scroll_oric propre). PASS.
- Non-régression défaut inchangée (czech 349/0, 406/0, HHGG, dragontroll V5, advent V5).

## [0.36.1] - 2026-08-14 — Fix `s_scroll_oric` : scroll borné (corrige un débordement d'écran + débloque le crash V5 du banking)
### Bug corrigé (correctif inconditionnel, améliore le build par défaut)
`s_scroll_oric` calculait le nombre de lignes à déplacer par `X = s_screen_height − (window_start_row+1) − 1`
**sans borne**. Quand une **fenêtre haute V5** couvre tout l'écran (`window_start_row+1 == s_screen_height`,
observé sur *advent_punyinform* : `protect=28`, `height=28`), la soustraction **sous-déborde**
(`28−28−1 = −1 = $FF`) → le scroll **balaie ~256 lignes** au lieu de ~26, écrivant de `$BB80`
jusqu'à `~$E358`, **bien au-delà de l'écran**. **Fix** : garde qui saute le scroll si le nombre
de lignes à déplacer est ≤ 0 (`bcc`/`beq` → `sso_nothing`) — quand la fenêtre haute couvre tout,
il n'y a rien à scroller.
### Impact
- **Build par défaut** : le débordement écrivait dans `$C000-$DFFF` (RAM alors **inutilisée** →
  inoffensif mais **incorrect**). Correction de propreté. **Non-régression : czech.z3 349/0,
  czech.z5 406/0, HHGG jouable, dragontroll.z5 (V5) jouable, advent_punyinform.z5 (V5) jouable.**
- **Banking (`-DORIC_BANKING`)** : le débordement écrasait le **vmap ($DE00) et les blocs VMEM
  ($C000-$DDFF)** → `z_pc` déraillait → décodait l'opcode `$B7` (0OP:restart) → `jmp` reset dans un
  bloc RAM → **`JAM` (CPU figé)**. **CRASH V5 RÉSOLU** : advent en banking **ne crashe plus**, boote,
  affiche la salle complète, **répond aux commandes** ; vmap vérifié **propre** (0 entrée hors-story).
### Diagnostic (méthode)
Trace CPU en anneau (`--trace-ring`/`--trace`) → signature du JAM (`FFA3 JMP $DAEE` → bloc RAM) ;
opcode fautif `$B7` lu par z_pc à une page banked au contenu erroné ; **bisection temporelle**
(`--dump-ram-at`) situant la corruption du vmap à ~206 M cycles pendant le traitement de « east » ;
trace fine → l'instruction corruptrice **`sso_st: STA $DE30,Y`** (= `s_scroll_oric`) ; lecture de
`s_screen_height`/`window_start_row+1` → sous-débordement du compteur. Aucune supposition retenue.
### Reste (non bloquant, hors banking)
Artefacts d'affichage sous scroll/[MORE] intensif (bug **num_rows/word-wrap** pré-existant, cf.
v0.33.0/v0.34.0) — plus visibles en banking (boot plus lent → écran qui se remplit) ; à polir avant
d'envisager d'activer le banking par défaut.

## [0.36.0] - 2026-08-14 — Banking $C000-$DFFF : implémenté en flag opt-in expérimental (`-DORIC_BANKING`, OFF par défaut)
### Ce qui est fait
Le **banking de la RAM overlay `$C000-$DFFF`** (RAM sous la ROM BASIC, exposée quand
`read_track_sector` met ROMDIS off via `$0314=$80`, persistante sous SEI) est implémenté
selon l'approche « skip du trou » étudiée en v0.34.0 :
- Les blocs VMEM occupent `vmap_first_ram_page..$B3FF` **puis** `$C000..$DDFF` ; le **trou
  matériel charset/écran `$B400-$BFDF`** (12 pages) est **sauté** (`+$0C`) aux **3 sites**
  qui dérivent une page RAM d'un index vmap (`load_blocks_from_index`, et les 2 chemins de
  `read_byte_at_z_address`). Les autres dérivations (`opt_optimize_vmem`, `print_vm_map`)
  ne sont pas compilées sur Oric (`OPTIMIZE_VMEM`/DEBUG absents).
- `first_banked_memory_page = $E0` → le **chemin cache** (banking C128/REU) reste
  inatteignable (aucun bloc n'atteint `$E0`) : tous les blocs `$C000+` sont **adressés
  directement** (RAM plate, romdis off).
- `vmap_max_entries` **soustrait les 12 pages** du trou ; le **vmap est relogé** `$DE00-$DE80`
  (au sommet de la RAM overlay, au-dessus des blocs) car `$B000` tombe désormais dans la
  zone des blocs.
- **Gain mesuré (HHGG)** : `vmap_max_entries` passe de **42 à 59 blocs** (~40 % de faults
  disque en moins). **Vérifié on-hardware** : dump RAM en cours de jeu montrant `$C000-$DDFF`
  peuplé de données de story + vmap correct à `$DE00` + **intro et parser HHGG parfaits**.

### Pourquoi OFF par défaut (honnêteté)
Le banking est **validé en V3** (HHGG jouable, texte propre, banking effectivement engagé)
mais **REGRESSE en V5** : `advent_punyinform.z5` (qui tourne parfaitement sans banking,
cf. v0.35.0) **crashe au moment du traitement de la saisie** (`east` → l'émulateur sort ;
sans banking la même commande donne « Inside Building »). Diagnostic mené (trace CPU en
anneau, dumps RAM, mapping des labels) : le blocage observé sans touche est le **[MORE]
inhérent** à la longue intro (CPU en attente clavier dans `kernal_getchar`), **pas** un
thrash VMEM (vmap stable) ni une boucle disque ; mais **avec** une commande, advent V5
crashe. La cause exacte n'a **pas** pu être isolée par inspection (chemins de lecture,
`set_z_pc`/`get_page_at_z_pc` via `read_byte_at_z_address`, trick EOR#1 intra-bloc : tous
vérifiés cohérents avec le skip). **Décision : gating opt-in** — le défaut reste le
comportement stable v0.35.0, le banking devient expérimental à déboguer (spécifique V5)
avant activation.

### Portée
- **Défaut (sans `-DORIC_BANKING`)** : `VMEM_END_PAGE=$B0`, vmap `$B000`, `first_banked=$C0`,
  aucun skip → **identique fonctionnellement à v0.35.0**.
- **`-DORIC_BANKING`** : `VMEM_END_PAGE=$DE`, vmap `$DE00`, `first_banked=$E0`, skip du trou.
- Fichiers : `constants-oric.asm` (first_banked, vmap), `ozmoo.asm` (VMEM_END_PAGE,
  soustraction du trou dans le calcul `vmap_max_entries`), `vmem.asm` (3 sites de skip).

### Tests (build par défaut)
- Non-régression **complète, verte** : **czech.z3 349/0, czech.z5 406/0**, **HHGG jouable**
  (V3), **dragontroll.z5 jouable** (V5), **advent_punyinform.z5 jouable** (V5, `> east` →
  « Inside Building », restauré).
- Build `-DORIC_BANKING` : assemble (Z3/Z5) ; HHGG V3 jouable + banking engagé (vérifié) ;
  advent V5 crash (connu, cf. ci-dessus).

## [0.35.0] - 2026-08-14 — ★★★★ VRAI JEU V5 JOUABLE SUR ORIC (objectif d'origine atteint) ★★★★
### La chaîne V5 interactive est validée de bout en bout sur un vrai jeu
Jusqu'ici la **V5** était prouvée par la conformité (`czech.z5` 406/0) et un **gros jeu réel
en V3** (HHGG) était jouable ; le croisement « **vrai jeu V5 jouable** » — l'objectif de
l'[étude de faisabilité](../ETUDE_FAISABILITE_ORIC_V5.md) — restait à démontrer. C'est fait.
- **`advent_punyinform.z5`** (Colossal Cave, PunyInform, **V5, 80 Ko**) **boote en VMEM
  depuis la disquette Sedoric, affiche son intro et RÉPOND aux commandes tapées** :
  ```
  Welcome to Adventure!  /  ADVENTURE  /  At End Of Road
  You are standing at the end of a road before a small brick building...
  > east
  Inside Building
  You are inside a building, a well house for a large spring.
  There are some keys on the ground here. ... a shiny brass lamp ... an empty bottle here.
  > 
  ```
  Valide **toute la chaîne V5 interactive** : pagination VMEM d'un gros jeu multi-pistes +
  saisie ligne **`@aread`** (opcode `read` V5, format buffer où **l'octet 1 = nombre de
  caractères**, distinct du terminateur-0 de `@sread` V3) + écho + **tokenisation V5**
  (adresses de dictionnaire packées ×4) + parser.
- Confirmé aussi sur **`dragontroll.z5`** (petit jeu V5 à parser) : `? n` échoé →
  déplacement de salle (« You are in the desert »).

### Aucune modification du moteur — diagnostic
La saisie ligne V5 (`@aread`) **fonctionnait déjà** : le path `read_text`/`read_char`
d'Ozmoo rejoint le **même `kernal_getchar` Oric** que la V3, et `init_read_text_timer`
sort immédiatement quand aucun timer n'est demandé (`.read_text_time == 0`). L'échec initial
observé sur le gros jeu était un **artefact de test** (frappe injectée *avant* l'armement de
`@read`, pendant que le jeu paginait encore) et non un bug : en tapant après l'armement, le
jeu répond correctement.

### Tests
- **Nouveau** `test-oric/v5_play_test.sh` — jouabilité V5 **déterministe** : build interp V5
  VMEM → disquette dragontroll → boot + commande `n` → assertions (intro V5, écho `? n`,
  changement de salle « desert »). **PASS**. Support versionné (`examples/dragontroll.z5`),
  rapide (~90 M cycles), sans pagination pendant la saisie (fenêtrage clavier reproductible).
- Non-régression VMEM : **czech.z3 349/0, czech.z5 406/0** (inchangé — aucun code touché).

### Note (limite du test automatisé)
Le gros jeu `advent_punyinform.z5` (80 Ko) est validé **manuellement** mais pas retenu comme
test headless : son long boot + pagination rend l'instant d'armement de `@read` peu
prédictible, donc le fenêtrage d'injection clavier moins déterministe. `dragontroll` couvre
**exactement la même chaîne V5** de façon reproductible ; le gros jeu reste une démo manuelle.

## [0.34.1] - 2026-08-13 — Doc : README du portage (dépôt public)
- **`README-ORIC.md`** : présentation du portage ORIC (état, architecture, build & run,
  tests, limitations, licence/crédits Ozmoo).
- **`README.md`** : bannière en tête pointant vers le README de portage (visible sur la
  page d'accueil GitHub), README Ozmoo d'origine préservé en dessous.
- Publication du dépôt : `benedictemarty/ozmoo-oric` (public, branche par défaut
  `oric-port`), `upstream` = `johanberntsson/ozmoo`.

## [0.34.0] - 2026-08-13 — Affichage : scroll respecte la status-line (fin des lignes dupliquées)
### L'artefact de duplication au scroll est corrigé
Les longues lignes word-wrappées s'affichaient **en double** après un scroll (préfixe
partiel + ligne complète, ex. `Infocom...a LAXY` / `Infocom...a science` ; `You wake` /
`You wake up...`). Diagnostic : **`s_scroll_oric` scrollait TOUT l'écran, y compris la
status-line (row 0)** — ce que le modèle de fenêtres V3 d'Ozmoo n'attend pas (la status
est l'« upper window », fixe). La status-line scrollée puis redessinée désynchronisait le
comptage de lignes → une ligne parasite insérée à chaque scroll. Confirmé empiriquement :
texte PROPRE avant le 1er scroll, dupliqué juste après.
### Fix (`screenkernal-oric.asm`)
`s_scroll_oric` **protège désormais `window_start_row + 1` lignes du haut** (= 1 en V3, la
status-line) : il déplace les lignes `[protect+1 .. height-1]` → `[protect .. height-2]`
et efface la dernière, laissant la row 0 intacte (comme le `.s_scroll` du C64 qui protège
`window_start_row + 1` lignes). Réécrit en code auto-modifiant (adresses src/dst patchées)
pour ne pas toucher la page zéro. Résultat : **intro HHGG et descriptions de salle
s'affichent proprement**, sans duplication, status-line fixe.
### Tests
- Non-régression VMEM : **czech.z3 349/0, czech.z5 406/0** (czech scrolle beaucoup).
- **hhgg_play_test.sh** PASS ; vérif manuelle intro + description de chambre = texte net.

## [0.33.0] - 2026-08-13 — Saisie ligne : Backspace/Delete efface à l'écran
### Effacement visuel de la saisie corrigé
La touche **Backspace ou Delete** (toutes deux mappées sur le DEL Oric col5/row5 → ASCII 8
dans l'émulateur) fonctionnait déjà **logiquement** (le buffer `@sread` était corrigé, le
parser recevait le bon texte) mais **pas visuellement** : `read_text` envoie le caractère
delete (8) à `s_printchar`, or l'`s_printchar` Oric ne le gérait pas → il l'affichait comme
un blanc et **avançait** le curseur (`>waix t` au lieu de `>wait`). **Fix
(`screenkernal-oric.asm`)** : `s_printchar` gère `$08` (`spc_backspace`) = recule d'une
colonne et écrit un espace (efface le caractère). Résultat : `>wait` propre à l'écran, en
phase avec le buffer.

### Tests
- **`test-oric/hhgg_play_test.sh`** étendu : la 2e commande devient `waix`+**Backspace**+`t`
  → doit afficher `>wait` PROPRE et le parser répondre `Time passes...` → **PASS**.
- Non-régression VMEM : czech.z3 349/0 (le char `$08` n'apparaît pas dans le texte de czech).

### Note
- Reste un artefact word-wrap à l'affichage des longues lignes (lignes dupliquées :
  préfixe + ligne complète), dû à `num_rows=0` non initialisé (gestion de fenêtres V3
  incomplète) — chantier séparé, non bloquant pour jouer.

## [0.32.0] - 2026-08-13 — ★★★★ HHGG JOUABLE SUR ORIC : gros jeu V3 en VMEM + @sread ★★★★
### L'aboutissement : un vrai jeu Infocom tourne et se joue sur Oric
**The Hitchhiker's Guide to the Galaxy** (release 59, **111 Ko**, V3) **boote en VMEM
depuis la disquette Sedoric, affiche son intro et RÉPOND aux commandes tapées** :
```
THE HITCHHIKER'S GUIDE TO THE GALAXY / Release 59 / Serial 851108
You wake up. The room is spinning... It is pitch black.
> turn on light
[description de la chambre : lavabo, chaise, robe de chambre, tournevis...]
> wait
Time passes...
```
Valide **bout-en-bout** : pagination VMEM d'un gros jeu multi-pistes + **saisie ligne
`@sread`** (écho + RETURN + tokenisation dictionnaire + parser multi-mots) + table
clavier complète. Non-régression : czech.z3 349/0, czech.z5 406/0.

### Deux bugs corrigés pour les GROS jeux
- **`ozmoo.asm` `VMEM_END_PAGE` non défini pour l'Oric → défaut $00 (=$100)**. Les blocs
  VMEM non-bankés pouvaient s'étaler jusqu'à `$FFFF` et **écraser le vmap ($B000), le jeu
  de caractères matériel Oric ($B400/$B800) et l'écran ($BB80)**. Invisible avec czech
  (petite dynmem → `vmap_first_ram_page=$3E`, 16 blocs restant sous $5E00) ; **fatal avec
  HHGG** (grosse dynmem → `vmap_first_ram_page=$5C`, `vmap_max_entries=82` → blocs jusqu'à
  $FF, vmap corrompu → bloc dynmem 1 demandé → `readblock` boucle à l'infini). **Fix :
  `VMEM_END_PAGE = $B0`** (blocs non-bankés `vmap_first_ram_page..$AFFF`, vmap $B000-$B0CC
  juste au-dessus, sous le charset). Banking $C000+ non encore implémenté (< $C0).
- **`tools/build_game_disk.py` : placement mono-bloc limité à la piste 20**. HHGG (~24
  pistes statiques) déborde. **`_geometry(skip_tracks=...)`** réserve désormais la piste
  système Sedoric (20) **et les pistes du fichier interpréteur AUTO** (calculées depuis
  sa taille, alloué par sedoric_inject dès la piste 21) → la story les saute (octet
  disk_info=0 ⇒ `readblock .next_track`). HHGG : story sur pistes **15-19 + 27-45**,
  interp sur 21-26, système 20. Gardes ajoutés : `disk_info` ≤ buffer version (71 o en
  V3) et piste config ≤ 512 o. `readblock_full` (Python) valide les 404 secteurs.

### Ajouté
- **`test-oric/hhgg_play_test.sh`** : build interp VMEM + `build_game_disk` + boot headless
  Sedoric+Microdisc + tape « turn on light » puis « wait » → assertions intro HHGG
  présente ET parser répond (« Time passes ») → **PASS**. Le fichier jeu (commercial)
  n'est PAS versionné : attendu à la racine (`/home/bmarty/42/hhgg_r59.dat`), argument
  optionnel.

### Reste (cosmétique / optimisation)
- Léger artefact d'affichage au scroll (redraw de ligne d'entrée) — non bloquant.
- Banking `$C000-$FFFF` (RAM overlay sous ROM) pour plus de blocs en RAM (moins de
  thrashing disque) ; face 1 (`read_track_sector` side 0) pour jeux > face 0.

## [0.31.0] - 2026-08-13 — Clavier : table complète (prérequis saisie ligne @sread)
### Table clavier Oric complétée — lettres + RETURN + DELETE
La table `krc_to_ascii` (`keyboard-oric.asm`) était **quasi vide** (≈24 touches : chiffres
+ quelques signes + 1 seule lettre), suffisante pour czech (`read_char` = n'importe quelle
touche) mais **PAS pour la saisie ligne** `@sread`/`@aread` d'un vrai jeu (taper des mots).
Reconstruite intégralement comme **inverse de `char_map`** (`~/Oric1/src/io/keyboard.c`,
matrice 8 col × 8 lignes, dérivée des tables ROM `$FF70`/`$FFB0`) :
- **26 lettres** en minuscules (les jeux Z-machine saisissent en minuscule ; écran Oric
  en ASCII standard), 10 chiffres, espace, ponctuation.
- **RETURN** (col7,row5) → `$0d` (13) : caractère terminateur de `read_text`.
- **DELETE** (col5,row5) → `$08` (8) : touche delete attendue par Ozmoo (`read_text`).
- `$00` sur les modificateurs (SHIFT/CTRL/FUNCT row4), flèches (col4), ESC (col1,row5).

Le chemin saisie ligne est ainsi complet au niveau composant : `read_text` (text.asm)
→ `read_char` → `getchar_and_maybe_toggle_darkmode` → `kernal_getchar` (anti-rebond) →
`read_key` (table complète) ; écho via `s_printchar` (validé) ; Enter=13 termine ;
delete=8 efface.

### Tests
- **`test-oric/kbd_table_test.sh`** (nouveau) : injecte 18 touches via `--type-keys` →
  `read_key` (harnais brut `kbd_read.asm`) doit renvoyer l'ASCII attendu. Couvre
  chiffres, 12 lettres, espace, RETURN=13, DEL=8 → **PASS**. `kernal_getchar` (chemin
  réel avec anti-rebond) vérifié pour 'a'/'n' séparément.
- Non-régression VMEM disque : **czech.z3 349/0** (le module clavier est dans le build).

### Limite (honnêteté)
- Validé au niveau **composant** (read_key/kernal_getchar renvoient les bons codes). Le
  cycle complet `@sread` (écho ligne + Enter + tokenisation dictionnaire + parsing) n'est
  **pas** testé bout-en-bout faute de story interactive compilable (pas d'Inform 6 dispo ;
  czech/oztest = read_char, pas de saisie ligne). À revalider sur un vrai jeu V5.

## [0.30.0] - 2026-08-13 — ★★★ V5 EN VMEM : czech.z5 PASSE 406/0 DEPUIS LE DISQUE ★★★
### L'objectif du projet — interpréteur V5 paginé sur Oric — est DÉMONTRÉ
La version **V5** du testeur de conformité (`czech.z5`) tourne de bout en bout en VMEM
depuis la disquette Sedoric et rend **`Performed 425 tests. Passed: 406, Failed: 0.
Didn't crash: hooray!`**. Valide le chemin V5 complet : **adresses packées ×4**,
**objets 14 octets / 63 propriétés par défaut / 48 attributs** (`calculate_object_address`
sous `Z4PLUS`), en-tête V5, opcodes étendus (`call_xn`, `throw`, `set_colour`,
`erase_line`, `print_table`…). Non-régression V3 : `czech.z3` toujours **349/0**.

### Ajouté (module écran Oric — coutures V5 manquantes)
- **`screenkernal-oric.asm` `s_erase_line_from_cursor`** : efface du curseur à la fin
  de la ligne courante (colonnes `[zp_screencolumn .. s_screen_width-1]`). Requis par
  `z_ins_erase_line` (opcode `erase_line 1`) sous `Z4PLUS`.
- **`screenkernal-oric.asm` `z_ins_set_colour`** : STUB no-op (l'Oric est en attributs
  série `NO_COLOUR_MAP` ; la couleur premier plan/fond par cellule est différée — à
  étoffer via insertion d'attributs série). set_colour ne stocke pas de résultat ;
  opérandes déjà consommées → `rts` fonctionnel. Débloque l'assemblage `-DZ5`.

### Outillage
- **`test-oric/vmem_disk_run.sh`** : détecte la version Z (octet 0 de l'en-tête) →
  flag `-DZ<n>` automatique (V3/V5) ; nettoie les captures d'une run précédente ;
  assertion générique `FAILED: 0` + absence de ligne `ERROR` (au lieu du 349 codé en
  dur). Pipeline V5 identique à V3 (`build_game_disk.py`).

### Note
- `praxix.z5`/`strictz.z5` (autres testeurs V5) ont un format de sortie et une gestion
  d'entrée `@read` (ligne) différents de czech → non validés par ce harnais (czech-
  spécifique). czech.z5 = testeur de conformité exhaustif, preuve V5 suffisante.
- Reste : saisie ligne `@sread`/`@aread` (écho/Enter/parsing) sur un vrai jeu ; story
  multi-faces (`read_track_sector` force side 0) ; tester un V5 réel (InvisiClues…).

## [0.29.0] - 2026-08-13 — ★★★ czech PASSE 349/0 EN VMEM DEPUIS LE DISQUE ★★★
### Les 7 échecs VMEM résolus — la pagination disque est PARFAITE
czech.z3 rend désormais **`Performed 368 tests. Passed: 349, Failed: 0. Didn't crash:
hooray!`** en VMEM depuis la disquette Sedoric — **identique à la voie B tape**. Le
verdict passe de 337/7 (v0.28.0) à **349/0**, et 368 tests s'exécutent (vs 363 : les
5 tests objets qui déraillaient tournent maintenant).

### Cause racine : collision `vmap_buffer` ↔ `print_buffer2` (page $02)
La relocalisation du vmap en page $02 (fix #3 de v0.28.0) l'avait placé **à $0200,
PILE sur `print_buffer2`** (buffer de ligne écran) — ainsi que sur `keyboard_buff`
($0277), `key_repeat`, `charset_switchable`. Conséquence : `print_line_from_buffer`
**écrasait le vmap à CHAQUE impression de texte**. Une fois le vmap corrompu, les
faults suivants mappaient les blocs statiques sur de **mauvaises pages RAM** →
`z_pc` lisait le mauvais bloc → **opcodes erronés exécutés** (ex. un `insert_obj
Obj4 Obj1` décodé et exécuté *pendant la section Jumps*, corrompant l'arbre d'objets
que les tests get_parent/get_sibling/get_child/jin lisent ensuite). D'où les 7 échecs
**tous dans la section OBJECTS** (et non « high memory » comme supposé) :
[145],[151],[152],[156],[164],[165],[213].

### Correctif
- **`constants-oric.asm`** : `vmap_buffer` relocalisé de `$0200` (page $02, surchargée)
  vers **`$B000-$B0CC` (RAM haute libre)** — au-dessus de la zone des blocs VMEM
  non-bankés (`vmap_first_ram_page=$3E` .. `+2*vmap_max_entries=$A5`) et **sous le jeu
  de caractères matériel Oric** (`CHARSET_STANDARD=$B400`, `CHARSET_ALT=$B800`). Zone
  `$A600-$B3FF` prouvée libre (aucun symbole, hors blocs VMEM et charset).

### Méthode (diagnostic outillé, sans deviner)
- Repro + capture des 7 `ERROR [n] Expected X; got Y` par **screenshots périodiques**
  (`test-oric/vmem_disk_run.sh`). Décodage de la table d'objets de czech.z3 → les
  valeurs « got » = objets voisins (décalage).
- **Bisection temporelle** par `--dump-ram-at` : dynmem PARFAITE à 20M, table objets
  corrompue dès 34M (section Jumps) selon le pattern EXACT d'un `insert_obj`.
- **Trace CPU** (`-b 29e3 --trace-ring`) : la boucle de dispatch normale décode un vrai
  `insert_obj 8 5` depuis `(z_pc_mempointer),y` → z_pc pointait le mauvais bloc.
- Dump du **vmap** ($0200) : valait `05..14` après init, tout à zéro après impression →
  isolé à la collision `print_buffer2`. Hypothèse « raccourci z_pc EOR #1 » **écartée**
  par test (flag debug `ORIC_NO_ZPC_SHORTCUT` : échecs inchangés).

### Tests
- **VMEM disque** : `test-oric/vmem_disk_run.sh` (build VMEM + `build_game_disk` + run
  headless Sedoric+Microdisc + assertion `PASSED: 349, FAILED: 0`) → **PASS**.
- **Non-régression voie B** (non-VMEM tape) : `czech_test.sh` → **PASS 349/0** (le vmap
  n'existe qu'en build VMEM ; la relocalisation n'affecte pas le non-VMEM).

## [0.28.0] - 2026-08-13 — ★★ JALON : czech TOURNE EN VMEM DEPUIS LE DISQUE ★★
### Le cœur du projet est démontré
czech.z3 s'exécute **de bout en bout en VMEM** sur Oric+Sedoric : la z-machine pagine
la mémoire statique depuis la disquette (WD1793) à la demande. Verdict :
**`Performed 363 tests. Passed: 337, Failed: 7. Didn't crash: hooray!`** (contre 349/0 en
voie B tape ; 7 blocs restent à raffiner mais **aucun crash**). Première exécution VMEM
réelle → valide `read_track_sector` assembleur, `readblock`, `load_suggested_pages`,
la piste config et le pipeline `build_game_disk` complet.

### Trois bugs corrigés (en plus du SEI de v0.27.0)
- **`ozmoo.asm prepare_static_high_memory`** : `sta vmap_used_entries : tax` étaient
  **hors** du bloc `!if SUPPORT_REU = 1` → en build non-REU (Oric) ils écrasaient
  `vmap_used_entries` (16) par `npreloaded` (0). Remis dans le bloc. Bug Ozmoo générique
  révélé par la cible non-REU.
- **`constants-oric.asm`** : `vmap_buffer` était laissé à `$0334` (valeur C64, `>>> PORT
  TODO`) → **collision avec la page système $03 de l'Oric** (I/O VIA/Microdisc +
  workspace ROM/Sedoric) qui écrasait le vmap. **Relocalisé en page $02** (`$0200-$02CC`),
  libre une fois l'interpréteur maître (SEI).
- **`tools/build_game_disk.py`** : le disque doit contenir **uniquement la portion
  STATIQUE** de la story (la dynmem est chargée à part via le fichier AUTO). `readblock`
  lit le bloc `currentblock - nonstored_pages` → disque bloc 0 = 1er bloc statique
  (cf. make.rb `$story_file_cursor = $dynmem_blocks * $VMEM_BLOCKSIZE`). On place donc
  `story[nonstored_pages*256:]`.

### Méthode
- Debug outillé : halts `ORIC_DEBUG_VMAP`/`ORIC_DEBUG_CONFIG` (retirés), `da65` sur le
  binaire, `--dump-ram-at` + labels `.lab`, comparaison RAM↔story. Chaque bug isolé au
  niveau octet (config OK → vmap=0 → vmap non peuplé → mauvais blocs → dynmem-offset).

### Reste — diagnostic précis des 7 échecs
- Tests en échec : **[64],[145],[151],[152],[156],[164],[165],[213]**, tous dans la
  section czech **« high memory »**. **Pas un problème de données** : 16/16 blocs
  statiques vérifiés corrects en RAM. Pattern **valeurs inversées/décalées d'un élément**
  ([164]↔[165], [151]/[152]) → bug de **traduction d'adresse vmem** (`read_byte_at_z_address`,
  vmem.asm L744) pour certains accès high-memory. Voie B (non-VMEM) = 349/0 → opcodes OK.
  À instrumenter : chemin de lecture vmem non-REU. Puis vrais jeux V5.

## [0.27.0] - 2026-08-13 — EPIC 5 : L'INTERPRÉTEUR BOOTE DEPUIS DISQUE (Sedoric)
### JALON — Ozmoo se lance depuis une disquette Sedoric
- **`tools/build_game_disk.py`** : construit une disquette de jeu BOOTABLE (équivalent
  Oric+Sedoric de make.rb `build_S1`) : master Sedoric → `mfm2raw` → place story+config
  en **secteurs bruts** sur pistes hautes libres → injecte l'interpréteur+dynmem en
  **fichier AUTO** (`sedoric_inject`) + INIST autoexec `LOAD"OZMOO"` → `dsk_raw2mfm`.
  **Prouvé sur Phosphoric : le splash `OZMOO ORIC-0.1` s'affiche** (Sedoric boote →
  INIST charge et lance l'interp).
- **FIX critique (`ozmoo.asm` `.initialize`)** : `cli` → **`sei` sous `TARGET_ORIC`**.
  Le `cli` (hérité C64) réactivait les IRQ ; sous Sedoric, le **handler IRQ résident du
  DOS** déraillait pendant nos accès FDC bruts (`read_track_sector`) → crash (BRK, boucle
  ROM Sedoric). En SEI, **la lecture de la piste config marche : `disk_info` est
  correctement rempli** (`00 01 02 08…`). L'Oric tourne sans IRQ (clavier scruté).
  Non-régression voie B : **czech_test.sh PASS 349/0**.

### Découvertes (empiriques, Phosphoric)
- **Le DOS Sedoric ne vit que sur side 0 pistes {0, 20} + fichiers catalogue (7-10 sur
  SEDO40u) + pistes BASSES réservées hors catalogue** : effacer la piste 1 casse le boot,
  mais les **pistes 15+ sont sûres** → story/config placés à partir de la piste 15
  (`-DCONF_TRK=15`). Le catalogue seul (31 secteurs) sous-estime le réservé DOS.
- Amorçage EPROM : lit piste 0/sect 1 (secteur système Sedoric) → charge DOS.

### Reste (dernier verrou avant czech jouable en VMEM)
- **`load_suggested_pages` ne charge pas les blocs statiques** depuis le disque
  (RAM `$3E00+` reste à zéro) alors que `disk_info` est correct et la lecture config OK.
  À déboguer : parcours vmap / `readblock`→`read_track_sector` des pistes story (15-17).

## [0.26.0] - 2026-08-13 — EPIC 5 : pipeline Sedoric — AUTO file, mfm2raw, géométrie
### Décision
- Voie **bootstrap Sedoric minimal** retenue (interp = fichier AUTO). Coexistence avec
  les secteurs bruts story résolue : piste 20 = système, fichiers dès piste 21,
  pistes 1-19 libres pour la story (petit jeu).

### Ajouté
- **`tools/mfm2raw.py`** : extrait une image **MFM_DISK** (Phosphoric) → **RAW side-major**
  (inverse de `dsk_raw2mfm.py`) ; repère les secteurs par leurs address marks
  (`A1 A1 A1 FE`/`FB`). Indispensable pour partir d'un master Sedoric (fourni en MFM) et
  opérer en raw. **Test round-trip raw→MFM→raw = identité** ; validé sur `sedoric3.dsk`/
  `SEDO40u.DSK` (re-MFM reboote « SEDORIC V3.0 »).

### Mesuré (build VMEM `--vicelabels`)
- Binaire VMEM = **exactement $0500–$33FF** (12032 o), finit **pile à `story_start=$3400`**.
  `deletable_init=$3079` vit **dans la pile** (astuce deletable). ⇒ **fichier AUTO = interp
  + dynmem** (dynmem à $3400) sans chevauchement ; blocs statiques faultent à `$3E00+`.
  `sedoric_inject.py` load=$500 exec=$500 (=`program_start`).

### Découvert (géométrie — à trancher)
- Masters Sedoric fournis = **80 pistes/face** et pleins (pistes 1-19 occupées).
  `--disk-create` = blank **42 pistes** (géométrie `oric_disk.py`) mais **non bootable** ;
  `make_bootable_sedoric.sh` échoue dessus (timing 80 pistes). `read_track_sector` force
  side 0, seek libre → OK jusqu'à piste 79.

### Reste (prochain incrément)
- **`build_game_disk.py`** (façon make.rb) : master bootable → carte VTOC des secteurs
  libres → placer story+config (bruts) + marquer occupés → injecter interp AUTO + INIST
  autoexec → MFM. Marche de catalogue à rendre robuste (bornes). Puis **1re exécution VMEM**.

### Tests
- `mfm2raw` round-trip PASS ; suite `oric_disk.py` (5 tests) inchangée (PASS).

## [0.25.0] - 2026-08-13 — EPIC 5 : amorçage disque-only, analyse EPROM Microdisc
### Décision
- **Abandon de la cassette** : cible **disque-only** (un V5 ne tient pas en RAM). Choix
  utilisateur : boot « maison » (disque brut, sans DOS) — sous réserve de faisabilité.

### Analyse (reverse-engineering empirique de `microdis.rom`)
- Méthode : disque à **signatures uniques par secteur** (raw→MFM via `dsk_raw2mfm.py`),
  `oric1-emu --trace/--dump-ram-at`, désassemblage `da65`. Faits **prouvés** :
  - Reset EPROM = **$EB7E** ; overlay $E000-$FFFF visible, BASIC désactivée.
  - L'EPROM lit **piste 0 / secteur physique 1** dans un buffer à **$C013** (bloc de
    paramètres à `$C000` : track, sector=1, bufptr=$C013).
  - Ce secteur = **secteur système Sedoric** (en-tête + nom « SEDORIC » à `$C033`,
    géométrie), **pas du code**. L'EPROM le **valide** (`LDA $C033,x`…) puis **charge le
    DOS** en plusieurs lectures (8 observées : secteurs 1,1,3,3,2,1,3,3, multi-pistes)
    avant de lancer Sedoric (« SEDORIC V3.0 » à ~2 M cycles).
- **Conclusion** : l'EPROM **n'offre pas de hook générique** « charge+saute » ; son
  amorçage est un **protocole propre à Sedoric**. Un boot « 100 % maison sans DOS » exige
  de **leurrer ce protocole** (bien plus lourd qu'anticipé). Restent **inconnus** (non
  inventés) : signature exacte, séquence de chargement DOS, adresse de handoff.

### Impact / à décider
- Deux voies documentées dans `docs/PORTING_ORIC.md` §EPIC 5 : (1) boot maison intégral
  (désassembler le parseur `$E8xx` de l'EPROM → contrat minimal), (2) bootstrap Sedoric
  minimal (interp = fichier AUTO via `sedoric_inject.py`, puis story en secteurs bruts).
  **À re-trancher avec l'utilisateur** au vu du couplage EPROM↔Sedoric.

### Tests
- Aucun code moteur/outil modifié → suite `oric_disk.py` (5 tests) inchangée (PASS).

## [0.24.0] - 2026-08-13 — EPIC 5 voie A : couche VMEM (dynmem + vmem_data)
### Analyse (chemin boot VMEM Oric tranché)
- **La build VMEM assemble déjà** (`build-oric.sh`, exit 0, 12032 o) et les symboles se
  résolvent pour l'Oric : `config_load_address = vmem_cache_start = $2800` (RAM),
  `story_start = $3000`, `SCREEN_ADDRESS = $bb80`. Le chemin boot `deletable_init`
  (L2241-2276) est **générique** : il lit la piste config via `read_track_sector` (porté),
  reconstruit `disk_info`, `auto_disk_config`. `read_track_sector` **ignore le device**
  (mono-lecteur) → la valeur de `boot_device` (issue de `CURRENT_DEVICE`) est sans impact.
- **Blocage identifié & résolu (côté outils)** : en VMEM, `load_suggested_pages` charge
  les pages **statiques** depuis le disque, mais la **mémoire dynamique** (`nonstored_pages`,
  résidente à `story_start`) est chargée **séparément** — sur C64 via le boot-file
  préchargé. Sur Oric (chargement tape), il faut donc **tape = interpréteur + dynmem** ;
  les pages statiques faultent ensuite du disque via `readblocks`→`readblock`→WD1793.

### Ajouté (`tools/oric_disk.py`)
- **`story_vmem_layout()`** : calcule depuis l'en-tête Z-machine (`header_static_mem`,
  offset $0e/$0f) `nonstored_pages` (repro fidèle de `calc_dynmem_size`), `dynmem_blocks`
  (=nonstored/2) et `total_blocks` (512 o). Ex. czech.z3 : dynmem=10 pages (blocs 0-4),
  statiques 5-20.
- **`build_vmem_data()`** : port de make.rb (~L3517) — suggère TOUS les blocs statiques
  (0 préchargé) pour chargement au boot par `load_suggested_pages`. Format
  `[len_hi, len_lo, nb_sug, nb_pré] + octets-hauts + octets-bas`.
- **`story_dynmem_prefix()`** : octets de dynmem à charger à `story_start` via tape.
- `build_bootable_disk()` calcule et écrit le `vmem_data` réel dans la piste config ;
  la CLI émet aussi `<out>.dynmem` (préfixe dynmem pour la tape).

### Tests
- **`_vmem_layout_test()` : 4 profils VMEM** (dont czech.z3) — `nonstored_pages`/
  `dynmem_blocks` corrects, `vmem_data` bien formé (compteurs, longueur, octets-bas =
  blocs statiques), préfixe dynmem = nonstored_pages, config complète ≤ 512 o. Les 4
  tests précédents (2092/600/4352/1200 blocs) inchangés (PASS).

### Reste voie A (run réel)
- Assembler la tape VMEM = interpréteur + `.dynmem` à `story_start` ; convertir l'image
  en MFM (`dsk_raw2mfm.py`) ; booter tape+disque dans Phosphoric → **1re exécution VMEM**
  (les blocs statiques 5-20 doivent faulter du disque via WD1793).

## [0.23.0] - 2026-08-13 — EPIC 5 voie A : piste de config + chaîne de boot simulée
### Ajouté
- **`oric_disk.py build_config_track_bytes()`** : sérialise la piste de config (≤ 512 o,
  2 secteurs) au format lu par le boot VMEM (`ozmoo.asm` `deletable_init` L2241-2276) :
  `game_id(4) + octet-taille + disk_info complet + vmem_data`. L'octet-taille (+4) =
  `1 + len(disk_info)` ; le boot copie `taille-1` octets depuis +5 vers `disk_info`
  (donc `disk_info+0` = interleave). vmem_data minimal par défaut (0 bloc préchargé).
- **`oric_disk.py build_bootable_disk()`** : image BRUTE side-major **complète** =
  blocs story placés + **piste de config écrite** dans les 2 secteurs réservés de
  `CONF_TRK`. Renvoie `(raw, disk_info_full, placement, config_bytes)`.
- CLI `oric_disk.py` : produit désormais une image **bootable** (config_sectors=2 +
  piste config) et accepte un `game_id` optionnel ; imprime la piste de config.

### Découverte (clé de la 1re exécution VMEM)
- Le « boot loader » qui remplit `disk_info` **existe déjà** et est **générique** :
  `ozmoo.asm` `deletable_init` (L2241-2276, sous `!ifdef VMEM`) lit la piste config
  via **`read_track_sector`** (routine WD1793 **déjà portée & validée** !), copie
  `game_id`, reconstruit `disk_info`, puis `auto_disk_config`. Le portage Oric de cette
  étape ⇒ surtout définir `config_load_address`/`boot_device` pour l'Oric et vérifier
  `auto_disk_config`. Reste ensuite : charger l'interpréteur lui-même (tape→VMEM).

### Tests
- **`_bootable_disk_test()` : 1200 blocs** — **chaîne de boot COMPLÈTE simulée sans
  émulateur** : image bootable → relecture de la piste config depuis l'image (comme
  `read_track_sector`) → reconstruction de `disk_info` (comme la copie L2255-2274,
  octet-taille inclus) → `readblock_full` retrouve chaque bloc → **données lues ==
  story** + `game_id` vérifié. Round-trip 2092 + 600 + 4352 inchangés (PASS).

### Reste voie A
- Porter/vérifier l'assemblage du chemin boot L2241-2276 sous `TARGET_ORIC` + `VMEM`
  (`config_load_address`, `boot_device`, `auto_disk_config`).
- Charger l'interpréteur en RAM (tape) puis `jmp program_start` → **1re exécution VMEM**.
- Écriture image en MFM Oric (`~/Oric1/tools/dsk_raw2mfm.py`).

## [0.22.0] - 2026-08-13 — EPIC 5 voie A : disk_info COMPLET (save+story) validé
### Ajouté
- **`oric_disk.py build_full_disk_info()`** : construit le `disk_info` **complet**
  tel que l'interpréteur le reçoit en RAM — préambule global `[interleave, save_slots,
  ndisks=2]` + **entrée « disque de sauvegarde »** (8 octets, lastblock+1=0, 0 piste)
  en index 0 + **entrée story** en index 1. Structure déduite de `make.rb` (`config_data`
  init + `build_S1`). L'entrée save en tête est **indispensable** : c'est son passage via
  `.next_disk` qui réordonne `.blocks_to_go` en big-endian, ordre qu'attend la track-walk
  (cf. FINDING v0.21.0 — la story est donc toujours sur le disque d'indice ≥ 1).
- **`oric_disk.py readblock_full()`** : port **fidèle** du `readblock` **multi-disque**
  de `disk.asm` (disk-walk avec byte-swap big-endian, track-walk, recherche secteur
  physique interleave+skip). Reproduit le walk octet par octet sur le `disk_info` réel.
- CLI `oric_disk.py` : imprime désormais le `disk_info` COMPLET (préambule+save+story)
  en plus de l'entrée story seule.

### Tests
- **`_full_disk_info_test()` : 4352 blocs vérifiés** via la structure à 2 disques
  (interleave 0/1/3/5, tailles 1..600) — pour chaque bloc placé, `readblock_full`
  retrouve exactement la (piste, secteur) du placement. **Couvre le cas que le harnais
  mono-disque ne pouvait pas** (le walk n'était correct que story sur disque ≥ 1).
- Round-trip 2092 + image 600 blocs inchangés (toujours PASS).

### Reste voie A
- Init `disk_info` au boot depuis la piste config (`CONF_TRK`) → buffer `!fill 71`.
- Boot loader (charger interpréteur + init disk_info) → **1re exécution VMEM réelle**
  (validera enfin `readblock` assembleur avec cette structure complète).
- Écriture de l'image en MFM Oric (via `~/Oric1/tools/dsk_raw2mfm.py`) + en-tête config.

## [0.21.0] - 2026-08-13 — EPIC 5 voie A : constructeur écrit de vraies images
### Ajouté
- **`oric_disk.py build_disk()`** : écrit une image disque BRUTE side-major
  (2×42×17×256) avec les blocs story placés aux (piste, secteur) calculés, et renvoie
  les octets `disk_info`. CLI : `oric_disk.py <story> <out.raw> [interleave]`
  (à convertir en MFM via `dsk_raw2mfm.py`). Test : **600 blocs relus depuis l'image
  construite == story** (placement + écriture + readblock cohérents en Python).

### Finding (harnais readblock standalone)
- Tentative de valider le `readblock` **assembleur** on-Oric avec un `disk_info`
  mono-disque : `readblock` calcule une piste erronée. Cause identifiée : la track-walk
  attend `.blocks_to_go` réordonné (big-endian) par un passage dans `.next_disk`, qui
  n'a lieu que si le bloc n'est PAS sur le 1er disque. **Le `disk_info` réel place donc
  la story en disque ≥ 1** (entrée « save disk » en tête, cf. make.rb `build_S1`). La
  validation on-Oric doit utiliser la structure `disk_info` complète → contexte VMEM
  réel. Consigné dans `docs/PORTING_ORIC.md`. `readblocks_currentblock` confirmé
  little-endian (via `vmem.asm`).

### Tests
- Round-trip Python 2092 + 600 blocs OK. (czech/init_e2e/rts_sectorbase inchangés.)

## [0.20.0] - 2026-08-13 — EPIC 5 voie A : base secteur validée sur Oric (+1)
### Résolu (doc « Sedoric 3.0 à nu » + validation machine)
- **Numérotation des secteurs tranchée : 1-based.** Les ID physiques Sedoric/MFM
  vont de 1 à 17 (confirmé par la doc et par `dsk_raw2mfm.py` : `sec = si+1`), or
  `readblock` produit un secteur **0-based**. Fix : **`read_track_sector` ajoute +1**
  (dans `disk.asm` intégré ET `disk-oric.asm` standalone).
- **Validé SUR ORIC** : test `rts_sectorbase` — disque à contenu connu (octet0 = ID
  physique), lecture des secteurs 0/1/2 → affiche `123` (= octets des ID 1/2/3). PASS.
- Faits de format consignés (`docs/PORTING_ORIC.md`, `tools/oric_disk.py`) : géométrie
  Sedoric **2 faces × 42 pistes × 17 secteurs × 256 o** ; **piste 20 = piste système**
  (à éviter si Sedoric-compatible) ; le **skew physique** (pistes commençant aux
  secteurs 1,14,10,6,2…) est une optimisation de latence sans impact sur la correction
  (le WD1793 adresse par ID ; `dsk_raw2mfm` pose les ID 1..17 dans l'ordre).

### Tests
- `test-oric/rts_sectorbase.sh` (nouveau) : PASS. Round-trip Python 2092 blocs OK.
  czech PASS 349/0. init_e2e PASS. Build VMEM exit 0.

## [0.19.0] - 2026-08-12 — EPIC 5 voie A : socle constructeur de disque (vérifié)
### Ajouté
- **`tools/oric_disk.py`** : socle du constructeur de disque VMEM Oric. Porte
  fidèlement, en Python, le **placement des blocs story** (make.rb `add_story_data`)
  et le **mapping bloc VMEM → (piste, secteur)** (asm `readblock`), qui partagent la
  logique d'interleave. **Test de cohérence aller-retour : 2092 blocs vérifiés**
  (interleave 0/1/3/5, tailles 1..300) → la structure `disk_info` produite est bien
  celle qu'attend l'interpréteur.
- Format `disk_info` documenté (par disque) : `[taille, device, lastblock+1 (word),
  nbpistes] + octet/piste + nom` ; octet/piste = `64*(réservés/2)+secteurs_story`.

### Plan
- Voie A détaillée dans `docs/PORTING_ORIC.md` §EPIC 5 : (1) constructeur *(socle fait)*
  → en-tête config + écriture MFM Oric ; (2) init `disk_info` au boot depuis piste
  config ; (3) boot loader. Points à valider sur Oric : base secteur (0 vs 1-based
  Sedoric), gestion des 2 faces dans `read_track_sector`.

## [0.18.0] - 2026-08-12 — EPIC 3 : anti-rebond clavier
### Amélioré
- **`kernal_getchar` : anti-rebond.** `read_key` fait un scan LIVE de la matrice
  (pas de buffer KERNAL) → une touche maintenue serait renvoyée à chaque appel
  (des milliers/s dans la boucle de saisie `read_text`). Désormais `kernal_getchar`
  ne renvoie une touche que si elle diffère de la précédente (`kbd_last_key`) :
  nouvelle frappe ou relâchement intermédiaire ; touche tenue → 0. Une frappe
  physique = un caractère, comme GETIN sur C64.

### Tests
- czech **toujours PASS** (349/0). `init_e2e` PASS. Builds VMEM/non-VMEM exit 0.
- Note : la saisie ligne `@sread` (double-lettres, écho, Enter) reste à valider sur
  un vrai jeu — voir voie A (VMEM) pour charger de tels jeux.

## [0.17.0] - 2026-08-12 — EPIC 2 : inverse-vidéo (ligne de statut)
### Amélioré
- **`s_printchar` gère les codes reverse `$12` (on) / `$92` (off)** et applique
  `ora s_reverse` à chaque caractère imprimable (bit 7 = inverse vidéo sur Oric),
  comme `screenkernal.asm` sur C64. Avant, ces codes s'imprimaient en caractères
  parasites.
- **La ligne de statut V3 s'affiche en vidéo inverse pleine largeur** : dump RAM →
  row 0 = 40 octets bit 7 (`String ... SC:368 MV:349`). Rendu conforme aux jeux V3.

### Tests
- czech **toujours PASS** (349/0). `init_e2e` PASS. Builds VMEM/non-VMEM exit 0.

## [0.16.0] - 2026-08-12 — EPIC 2 : casse mixte correcte à l'écran
### Amélioré
- **Le texte s'affiche en casse mixte correcte** (minuscules + majuscules) au lieu de
  tout en capitales. czech : `Test numbers appear in [brackets].`,
  `print works or you wouldn't be seeing this.`, `Jumps`, `Variables`, `Arithmetic ops`...
- Cause : `translate_zscii_to_petscii` (`streams.asm`) appliquait la convention casse
  **PETSCII C64** (minuscule→$41-$5A, majuscule→$C1-$DA = inverse-vidéo sur Oric).
  Sur Oric l'écran est en **ASCII standard** → ZSCII imprimable = ASCII. Fix : garde
  `!ifndef TARGET_ORIC` autour de la conversion de casse (identité pour les lettres,
  la vérif de légalité renvoie le caractère inchangé). Aucun impact C64.
- Saisie (`translate_petscii_to_zscii`) : inchangée — `read_key` renvoie de l'ASCII
  minuscule pour une frappe normale, qui passe tel quel en ZSCII minuscule (correct
  pour les dictionnaires de jeu).

### Tests
- czech **toujours PASS** (349/0) après le fix casse (`czech_test.sh` : assertion rendue
  insensible à la casse). `init_e2e` PASS. Builds VMEM/non-VMEM exit 0.

## [0.15.0] - 2026-08-12 — JALON : czech PASSE (349/0), interpréteur INTERACTIF
### Majeur — VALIDATION DE CONFORMITÉ
- **L'interpréteur passe la suite de conformité Z-machine complète sur Oric.**
  czech.z3 (Comprehensive Z-machine Emulation CHecker) tourne intégralement et rend
  son verdict : **`PERFORMED 368 TESTS. PASSED: 349, FAILED: 0` — `DIDN'T CRASH: HOORAY!`**
  Opcodes, décodage Z-string, table d'objets/propriétés, abbréviations, print/paddr,
  ligne de statut V3 (`SC:368 MV:349`) : tout est correct.
- **L'interpréteur est INTERACTIF** : le clavier Oric (`read_key` via `kernal_getchar`,
  déjà branché dans `getchar_and_maybe_toggle_darkmode`) fait avancer czech à chaque
  pause `@read_char`. La saisie fonctionne bout-en-bout.

### Tests
- `test-oric/czech_test.sh` : build + run headless avec touches périodiques (passe les
  pauses `@read_char`) + assertion `PASSED: 349, FAILED: 0`. **PASS.** Test de
  non-régression « en or » couvrant le cœur interpréteur entier.

### Reste (polish)
- Casse : texte tout en MAJUSCULES (mapping PETSCII→Oric) ; inverse-vidéo `$12`/`$92`.
- Saisie ligne `@sread` (écho + Enter + parsing) à valider sur un vrai jeu ;
  anti-rebond (`read_key` non débouncé — touche maintenue = répétition).

## [0.14.0] - 2026-08-12 — EPIC 2/5 : PREMIER TEXTE DE STORY LISIBLE SUR ORIC
### Majeur — JALON
- **Une story Z-machine s'affiche réellement et lisiblement sur Oric.** czech.z3
  (Comprehensive Z-machine Emulation CHecker) tourne et imprime son rapport :
  `CZECH: THE COMPREHENSIVE Z-MACHINE EMULATION CHECKER, VERSION 0.8`,
  `PRINT WORKS OR YOU WOULDN'T BE SEEING THIS.`, puis `JUMPS`, `VARIABLES`,
  `ARITHMETIC OPS`, `LOGICAL OPS`, `MEMORY`, `SUBROUTINES`, `OBJECTS`... Le décodage
  Z-string, le word-wrap et l'affichage bout-en-bout fonctionnent sur la machine.
- **Bug corrigé : `s_reverse` (`$b3`) non initialisé** dans `screenkernal-oric.asm`.
  Sur C64 c'est `screenkernal.asm` (non utilisé sur Oric) qui le met à 0. Non
  initialisé, il valait `$FF` ; or `print_line_from_buffer` fait `ora print_buffer2,y`
  (drapeau inverse-vidéo par caractère = `s_reverse`), donc **chaque caractère
  bufferisé était écrasé en `$FF`** (invisible). Seul le dernier caractère de
  chaque ligne survivait (`s_printchar` ignore `s_reverse`) → symptôme « 1 char
  erroné par ligne ». Fix : `s_init` zéro-initialise `s_ignore_next_linebreak`
  (3 o) + `s_reverse` (`$b0-$b3`), comme le C64.

### Méthode (instrumentation)
- Diagnostic par double journalisation `ORIC_LOG_CHARS` : le flux à l'entrée de
  `printchar_buffered` (décodé) était **parfait** (« RTRUE.RFALSE... »), prouvant
  que le décodeur Z fonctionnait et isolant le bug dans le word-wrap. Le dump écran
  hexa a révélé les octets `$FF` → cause racine `ora print_buffer2`.
- Instrumentation d'investigation retirée des fichiers partagés (`screen.asm` intact) ;
  seul le log `s_printchar` minimal reste dans `screenkernal-oric.asm` (OFF par défaut).

### Reste (cosmétique / suite)
- Texte tout en MAJUSCULES : mapping casse PETSCII→Oric (lettres min. ZSCII rendues
  en capitales). Inverse-vidéo réel (`$12`/`$92`) non géré dans `s_printchar`.
- czech atteint ensuite un `@read` et attend l'entrée clavier (à brancher :
  `kernal_readchar`/`getchar` → boucle de saisie ligne).

## [0.13.0] - 2026-08-12 — EPIC 2/5 : rendu écran validé ($93), Z-code exécuté
### Majeur
- **La couche écran Oric affiche du vrai texte dynamique.** Sans drapeau debug,
  l'init va jusqu'à la boucle Z-machine ; le **splash Ozmoo s'affiche proprement**,
  centré, sur l'Oric émulé :
  `OZMOO ORIC-0.1 / F1=DARKMODE / CTRL: D=RESET DEVICE# K=KEY REPEAT / 0-8=SCROLL SLOWNESS`
  (premières lettres en inverse vidéo = bit 7, correct sur Oric). Preuve que
  `s_printchar` gère le texte réel, l'inverse vidéo et le scroll.
- **`s_printchar` gère le code contrôle PETSCII `$93` (147 = clear-screen + home)**
  (`screenkernal-oric.asm`). Corrige les 2 caractères parasites en tête d'écran.

### Outillage
- Instrumentation debug `ORIC_LOG_CHARS` : journalise le flux d'octets reçus par
  `s_printchar` dans un buffer RAM ($6000, index $5f00), lisible via `--dump-ram-at`.
  A permis de décoder exactement ce qu'Ozmoo envoie à l'écran (OFF par défaut).
- Script `test-oric/run_game.sh` : build voie B **sans** drapeau debug + run headless,
  pour observer l'exécution du Z-code (story en argument, défaut `czech.z3`).

### Découvert (prochain chantier — couche texte Z-machine)
- Le Z-code **s'exécute** mais la sortie texte est **corrompue** : un caractère
  (souvent erroné) suivi d'un newline, en boucle, **identique pour czech ET strictz**
  (donc bug générique, pas story-spécifique). Ensuite le Z-code atteint un `@read`
  et **attend une touche** (profil : 60 % dans `kernal_delay_1ms` + scan `read_key`).
- Piste : décodage Z-string / table d'alphabet / couche word-wrap (streams/text.asm),
  ou préparation de la story attendue par Ozmoo (make.rb massage le fichier ; ici on
  concatène le `.z3` brut). À investiguer avec `ORIC_LOG_CHARS` + trace/gdb.

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
