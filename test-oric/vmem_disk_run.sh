#!/usr/bin/env bash
# Run une story Z-machine en VMEM depuis la disquette Sedoric (voie A) + captures
# ecran periodiques pour lire les lignes "ERROR [n] Expected X; got Y" qui defilent.
# La version Z (V3/V5...) est detectee sur l'octet 0 de l'en-tete de la story.
# Usage : vmem_disk_run.sh [story.z3|story.z5]
set -eu
cd "$(dirname "$0")/.."
EMU=~/Oric1/oric1-emu
ROM=~/Oric1/roms/basic11b.rom
MICRODISC=~/Oric1/roms/microdis.rom
MASTER=~/Oric1/disks/SEDO40u.DSK
OUT=temp/vmem
STORY=${1:-test/czech.z3}
mkdir -p "$OUT"
# Nettoyage des captures d'une run precedente (sinon les ERROR d'une autre story
# polluent l'analyse).
rm -f "$OUT"/s*.txt "$OUT"/nz*.txt "$OUT"/fx*.txt "$OUT"/final.txt 2>/dev/null || true

# Version Z-machine = 1er octet de l'en-tete -> flag -DZ<n> pour ACME.
ZVER=$(python3 -c "import sys;print(open(sys.argv[1],'rb').read(1)[0])" "$STORY")
echo "story=$STORY version Z=$ZVER"

FN="czech"; VS="Oric-0.1"
sed "s/@fn@/$FN/g" asm/file-name.tpl  > "temp/file-name.asm"
sed "s/@fn@/$FN/g" asm/walkthrough.tpl > "temp/walkthrough.asm"
sed -e 's/@0s@//g' -e 's/@1s@//g' -e 's/@2s@//g' -e 's/@3s@//g' -e "s#@date@#$(date +%d/%m/%Y)#g" \
    -e 's/@0c@/0/g' -e 's/@1c@/0/g' -e 's/@2c@/0/g' -e 's/@3c@/0/g' \
    -e "s/@vs@/$VS/g" asm/splashlines.tpl > "temp/splashlines.asm"

# 1) interpreteur VMEM, story sur pistes hautes (CONF_TRK=15)
cd asm
acme --setpc 0x0500 \
  -DTARGET_ORIC=1 -DZ${ZVER}=1 -DVMEM=1 \
  -DCACHE_PAGES=4 -DSTACK_PAGES=4 -DCONF_TRK=15 \
  -DMAJOR_VERSION_NO=0 -DMINOR_VERSION_NO=1 \
  --cpu 6502 --vicelabels ../"$OUT"/ozmoo-oric.lab \
  -o ../"$OUT"/interp.bin ozmoo.asm
cd ..

# 2) disquette de jeu bootable Sedoric + story/config bruts
python3 tools/build_game_disk.py "$MASTER" "$OUT/interp.bin" "$STORY" \
  "$OUT/czech.dsk" OZMOO deadbeef 15

# 3) run headless : Sedoric boote -> AUTO charge l'interp -> VMEM depuis disque.
#    Captures ecran toutes les 2M cycles pour attraper les ERROR qui defilent.
SHOTS=""
for c in $(seq 20 2 90); do
  SHOTS="$SHOTS --screenshot-text-at ${c}000000:$OUT/s${c}.txt"
done
KEYS=""
for c in 24 27 30 33 36 39 42 45 48 51 54 57 60 63 66 69 72 75 78 81 84 87; do
  KEYS="$KEYS --type-keys ${c}000000:' '"
done
eval "\"$EMU\" -r \"$ROM\" --disk-rom \"$MICRODISC\" -d \"$OUT/czech.dsk\" -n \
  $KEYS $SHOTS \
  --screenshot-text-at 91000000:\"$OUT/final.txt\" --cycles 92000000" >/dev/null 2>&1 || true

echo "=== VERDICT (VMEM depuis disque) ==="
grep -hiE 'PERFORMED|PASSED|HOORAY' "$OUT"/s*.txt "$OUT"/final.txt 2>/dev/null | sort -u || true
echo "=== ERREURS capturees (ERROR [n] Expected X; got Y) ==="
grep -hiE 'ERROR \[|Expected .*got' "$OUT"/s*.txt "$OUT"/final.txt 2>/dev/null | sort -u || echo "(aucune)"

# Assertion de non-regression : czech doit passer INTEGRALEMENT en VMEM disque.
# Generique V3/V5 : verdict present avec "FAILED: 0" et aucune ligne ERROR.
if grep -qiE 'FAILED: 0\b' "$OUT"/s*.txt "$OUT"/final.txt 2>/dev/null \
   && ! grep -qiE 'ERROR \[' "$OUT"/s*.txt "$OUT"/final.txt 2>/dev/null; then
  PASSED=$(grep -hoiE 'PASSED: [0-9]+' "$OUT"/s*.txt "$OUT"/final.txt 2>/dev/null | grep -oE '[0-9]+' | sort -rn | head -1)
  echo "PASS: $STORY conforme en VMEM depuis disque (Passed: $PASSED, Failed: 0)"
  exit 0
else
  echo "FAIL: verdict czech VMEM absent ou regression (attendu FAILED: 0)"
  exit 1
fi
