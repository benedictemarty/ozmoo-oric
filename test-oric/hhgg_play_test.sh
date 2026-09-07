#!/usr/bin/env bash
# Test JOUABILITE : HHGG (vrai jeu Infocom V3, 111 Ko, release 59) doit BOOTER en VMEM
# depuis la disquette Sedoric, afficher son intro, et repondre a une commande tapee au
# clavier -> valide bout-en-bout : pagination VMEM d'un gros jeu multi-pistes + saisie
# ligne @sread (echo + RETURN + parser dictionnaire) + table clavier complete.
#
# Le fichier jeu (commercial, NON versionne) est attendu a la racine du projet ; passer
# un autre chemin en argument au besoin.
set -eu
cd "$(dirname "$0")/.."
EMU=~/Oric1/oric1-emu
ROM=~/Oric1/roms/basic11b.rom
MICRODISC=~/Oric1/roms/microdis.rom
MASTER=~/Oric1/disks/SEDO40u.DSK
STORY=${1:-/home/bmarty/42/hhgg_r59.dat}
OUT=temp/vmem
mkdir -p "$OUT"
[ -f "$STORY" ] || { echo "SKIP: fichier jeu absent : $STORY"; exit 0; }

ZVER=$(python3 -c "import sys;print(open(sys.argv[1],'rb').read(1)[0])" "$STORY")

FN="hhgg"; VS="Oric-0.1"
sed "s/@fn@/$FN/g" asm/file-name.tpl  > "temp/file-name.asm"
sed "s/@fn@/$FN/g" asm/walkthrough.tpl > "temp/walkthrough.asm"
sed -e 's/@0s@//g' -e 's/@1s@//g' -e 's/@2s@//g' -e 's/@3s@//g' -e "s#@date@#$(date +%d/%m/%Y)#g" \
    -e 's/@0c@/0/g' -e 's/@1c@/0/g' -e 's/@2c@/0/g' -e 's/@3c@/0/g' \
    -e "s/@vs@/$VS/g" asm/splashlines.tpl > "temp/splashlines.asm"

# 1) interpreteur VMEM (version detectee), story sur pistes hautes (CONF_TRK=15)
cd asm
acme --setpc 0x0500 -DTARGET_ORIC=1 -DZ${ZVER}=1 -DVMEM=1 \
  -DCACHE_PAGES=4 -DSTACK_PAGES=4 -DCONF_TRK=15 -DMAJOR_VERSION_NO=0 -DMINOR_VERSION_NO=1 \
  --cpu 6502 --vicelabels ../"$OUT"/hhgg.lab -o ../"$OUT"/hhgg_interp.bin ozmoo.asm
cd ..

# 2) disquette de jeu (placement multi-pistes : story 15-19 + 27.., saute systeme 20 + interp)
python3 tools/build_game_disk.py "$MASTER" "$OUT/hhgg_interp.bin" "$STORY" \
  "$OUT/hhgg.dsk" HHGG cafedeed 15 | grep -E "story|interp AUTO|OK ->"

# 3) boot + intro (~70M) + commandes : "turn on light" (multi-mots) puis "waix"+
#    Backspace+"t" (teste l'effacement : doit donner "wait" -> "Time passes").
"$EMU" -r "$ROM" --disk-rom "$MICRODISC" -d "$OUT/hhgg.dsk" -n \
  --type-keys 74000000:'turn on light\n' \
  --type-keys 88000000:'waix\bt\n' \
  --screenshot-text-at 70000000:"$OUT/hhgg_intro.txt" \
  --screenshot-text-at 100000000:"$OUT/hhgg_play.txt" --cycles 102000000 >/dev/null 2>&1 || true

echo "=== INTRO (@70M) ==="; grep -iE "HITCHHIKER|Release 59|pitch black|>" "$OUT/hhgg_intro.txt" | head -5
echo "=== APRES COMMANDES (@100M) ==="; grep -v '^[[:space:]]*$' "$OUT/hhgg_play.txt" | tail -6

# Assertions : intro affichee ; parser a repondu ("Time passes") -> @sread + parser OK ;
# la ligne saisie s'affiche ">wait" PROPRE (pas ">waix t") -> Backspace efface bien.
ok=1
grep -qi "HITCHHIKER" "$OUT/hhgg_intro.txt" || { echo "FAIL: intro HHGG absente"; ok=0; }
grep -qi "Time passes" "$OUT/hhgg_play.txt" || { echo "FAIL: parser n'a pas repondu a 'wait'"; ok=0; }
grep -qE ">wait\b" "$OUT/hhgg_play.txt"     || { echo "FAIL: Backspace n'efface pas (attendu '>wait' propre)"; ok=0; }
if [ "$ok" = 1 ]; then
  echo "PASS: HHGG jouable (VMEM + @sread + parser + Backspace effacement OK) sur Oric"
  exit 0
else
  exit 1
fi
