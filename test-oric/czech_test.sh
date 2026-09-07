#!/usr/bin/env bash
# Test de conformité Z-machine : czech.z3 (Comprehensive Z-machine Emulation
# CHecker) doit tourner ENTIEREMENT sur Oric et afficher son verdict de reussite.
# Valide le coeur interpreteur (opcodes, decodage Z-string, objets, texte, statut)
# + l'interactivite clavier (avance a chaque pause @read_char via touches).
# Assertion : "PASSED: 349, FAILED: 0".
set -eu
cd "$(dirname "$0")/.."
EMU=~/Oric1/oric1-emu
BIN2TAP=~/Oric1/bin2tap
ROM=~/Oric1/roms/basic11b.rom
OUT=temp
mkdir -p "$OUT"

FN="czech"; VS="Oric-0.1"
sed "s/@fn@/$FN/g" asm/file-name.tpl  > "$OUT/file-name.asm"
sed "s/@fn@/$FN/g" asm/walkthrough.tpl > "$OUT/walkthrough.asm"
sed -e 's/@0s@//g' -e 's/@1s@//g' -e 's/@2s@//g' -e 's/@3s@//g' -e "s#@date@#$(date +%d/%m/%Y)#g" \
    -e 's/@0c@/0/g' -e 's/@1c@/0/g' -e 's/@2c@/0/g' -e 's/@3c@/0/g' \
    -e "s/@vs@/$VS/g" asm/splashlines.tpl > "$OUT/splashlines.asm"

cd asm
acme --setpc 0x0500 \
  -DTARGET_ORIC=1 -DZ3=1 \
  -DCACHE_PAGES=4 -DSTACK_PAGES=4 -DCONF_TRK=1 \
  -DMAJOR_VERSION_NO=0 -DMINOR_VERSION_NO=1 \
  --cpu 6502 --vicelabels ../$OUT/ozmoo-oric.lab \
  -o ../$OUT/interp.bin ozmoo.asm
cd ..

python3 - "$OUT/interp.bin" test/czech.z3 "$OUT/image.bin" "$OUT/ozmoo-oric.lab" <<'PY'
import sys, re
interp, story, out, lab = sys.argv[1:5]
ss=int(re.search(r'al C:([0-9a-fA-F]+)\s+\.story_start',open(lab).read()).group(1),16)
d=open(interp,'rb').read(); d+=b'\x00'*(ss-0x500-len(d))+open(story,'rb').read()
open(out,'wb').write(d)
PY

"$BIN2TAP" "$OUT/image.bin" --start 0x500 --exec 0x500 -o "$OUT/image.tap" >/dev/null

# Une touche toutes les ~3M cycles pour passer les pauses @read_char de czech.
KEYS=""
for c in 15 18 21 24 27 30 33 36 39 42 45 48 51 54 57 60 63 66 69 72; do
  KEYS="$KEYS --type-keys ${c}000000:' "
  KEYS="$KEYS'"
done
eval "\"$EMU\" -r \"$ROM\" -f -n -t \"$OUT/image.tap\" \
  --type-keys 2600000:'CLOAD\"\"\n' $KEYS \
  --screenshot-text-at 74000000:\"$OUT/czech.txt\" --cycles 75000000" >/dev/null 2>&1 || true

echo "=== VERDICT czech ==="
grep -iE 'PERFORMED|PASSED|HOORAY' "$OUT/czech.txt" 2>/dev/null || true

if grep -qi 'PASSED: 349, FAILED: 0' "$OUT/czech.txt" 2>/dev/null; then
  echo "PASS: czech.z3 conforme (349 tests reussis, 0 echec) sur Oric"
  exit 0
else
  echo "FAIL: verdict czech absent ou regression"
  grep -n '[^ ]' "$OUT/czech.txt" 2>/dev/null | tail -12
  exit 1
fi
