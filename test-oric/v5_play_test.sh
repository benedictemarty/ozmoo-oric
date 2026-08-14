#!/usr/bin/env bash
# Test JOUABILITE V5 : un vrai jeu Z-machine VERSION 5 doit BOOTER en VMEM depuis la
# disquette Sedoric, afficher son intro, et REPONDRE a une commande tapee au clavier
# -> valide bout-en-bout la chaine V5 : pagination VMEM + saisie ligne @aread (read,
# format buffer V5 : octet1 = nb de caracteres) + echo + tokenisation dictionnaire V5
# (adresses packees x4) + parser.
#
# Support par defaut : examples/dragontroll.z5 (petit jeu V5 a parser, VERSIONNE dans le
# depot -> test rapide et deterministe, sans pagination pendant la saisie). Passer un
# autre .z5 en argument au besoin (ex. un gros jeu comme advent_punyinform.z5).
#
# Note : un GROS jeu V5 reel a aussi ete valide manuellement (advent_punyinform.z5, 80 Ko :
#   "> east" echoe -> "Inside Building ... keys ... lamp ... bottle"). Il n'est pas retenu
#   comme test automatise car son long boot/pagination rend le fenetrage clavier moins
#   deterministe ; dragontroll couvre exactement la meme chaine V5 de facon reproductible.
set -eu
cd "$(dirname "$0")/.."
EMU=~/Oric1/oric1-emu
ROM=~/Oric1/roms/basic11b.rom
MICRODISC=~/Oric1/roms/microdis.rom
MASTER=~/Oric1/disks/SEDO40u.DSK
STORY=${1:-examples/dragontroll.z5}
OUT=temp/v5play
mkdir -p "$OUT"
[ -f "$STORY" ] || { echo "SKIP: fichier jeu absent : $STORY"; exit 0; }
[ -x "$EMU" ]   || { echo "SKIP: emulateur absent : $EMU"; exit 0; }

ZVER=$(python3 -c "import sys;print(open(sys.argv[1],'rb').read(1)[0])" "$STORY")
[ "$ZVER" = "5" ] || { echo "FAIL: $STORY n'est pas un jeu V5 (version=$ZVER)"; exit 1; }

FN="v5game"; VS="Oric-0.1"
sed "s/@fn@/$FN/g" asm/file-name.tpl   > "temp/file-name.asm"
sed "s/@fn@/$FN/g" asm/walkthrough.tpl > "temp/walkthrough.asm"
sed -e 's/@0s@//g' -e 's/@1s@//g' -e 's/@2s@//g' -e 's/@3s@//g' \
    -e 's/@0c@/0/g' -e 's/@1c@/0/g' -e 's/@2c@/0/g' -e 's/@3c@/0/g' \
    -e "s/@vs@/$VS/g" asm/splashlines.tpl > "temp/splashlines.asm"

# 1) interpreteur V5 VMEM, story sur pistes hautes (CONF_TRK=15)
cd asm
acme --setpc 0x0500 -DTARGET_ORIC=1 -DZ5=1 -DVMEM=1 \
  -DCACHE_PAGES=4 -DSTACK_PAGES=4 -DCONF_TRK=15 -DMAJOR_VERSION_NO=0 -DMINOR_VERSION_NO=1 \
  --cpu 6502 -o ../"$OUT"/v5_interp.bin ozmoo.asm
cd ..

# 2) disquette de jeu (Sedoric + story/config en secteurs bruts)
python3 tools/build_game_disk.py "$MASTER" "$OUT/v5_interp.bin" "$STORY" \
  "$OUT/v5.dsk" V5GAME cafe0002 15 | grep -E "story|interp AUTO|OK ->"

# 3) boot + intro puis commande de deplacement "n" (nord) -> le parser doit changer de
#    salle. dragontroll annonce "You can go n,e," et repond a "n" -> "You are in the desert".
"$EMU" -r "$ROM" --disk-rom "$MICRODISC" -d "$OUT/v5.dsk" -n \
  --type-keys 60000000:'n\n' \
  --screenshot-text-at 55000000:"$OUT/v5_intro.txt" \
  --screenshot-text-at 90000000:"$OUT/v5_play.txt" --cycles 92000000 >/dev/null 2>&1 || true

echo "=== INTRO (@55M) ==="; grep -iE "Dragon|troll|You see|\?" "$OUT/v5_intro.txt" | head -5
echo "=== APRES 'n' (@90M) ==="; grep -v '^[[:space:]]*$' "$OUT/v5_play.txt" | tail -6

# Assertions : intro V5 affichee ; echo de la saisie ("? n") -> @aread + clavier OK ;
# le parser a change de salle ("desert") -> tokenisation V5 + parser OK.
ok=1
grep -qi "Dragon"          "$OUT/v5_intro.txt" || { echo "FAIL: intro V5 absente (dragontroll)"; ok=0; }
grep -qE "\? *n\b"         "$OUT/v5_play.txt"  || { echo "FAIL: saisie non echoee (@aread V5 KO)"; ok=0; }
grep -qi "desert"          "$OUT/v5_play.txt"  || { echo "FAIL: parser V5 n'a pas traite 'n' (pas de changement de salle)"; ok=0; }
if [ "$ok" = 1 ]; then
  echo "PASS: jeu V5 jouable (VMEM + @aread + echo + tokenisation/parser V5) sur Oric"
  exit 0
else
  exit 1
fi
