#!/usr/bin/env bash
# Run "jeu" : build voie B non-VMEM SANS drapeau debug -> l'init va jusqu'a la
# boucle Z-machine et execute le Z-code. czech.z3 (testeur Z-machine) affiche
# des lignes de test -> preuve d'execution reelle du Z-code sur Oric.
set -eu
cd "$(dirname "$0")/.."
EMU=~/Oric1/oric1-emu
BIN2TAP=~/Oric1/bin2tap
ROM=~/Oric1/roms/basic11b.rom
OUT=temp
STORY=${1:-test/czech.z3}
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
  --cpu 6502 \
  --vicelabels ../$OUT/ozmoo-oric.lab \
  -o ../$OUT/interp.bin \
  ozmoo.asm
cd ..

python3 - "$OUT/interp.bin" "$STORY" "$OUT/image.bin" "$OUT/ozmoo-oric.lab" <<'PY'
import sys, re
interp, story, out, lab = sys.argv[1:5]
txt = open(lab).read()
story_start = int(re.search(r'al C:([0-9a-fA-F]+)\s+\.story_start', txt).group(1), 16)
d = open(interp,'rb').read()
pad_to = story_start - 0x500
assert len(d) <= pad_to, f"interp {len(d):#x} > {pad_to:#x} (story_start={story_start:#x})"
d = d + b'\x00'*(pad_to - len(d))
d += open(story,'rb').read()
open(out,'wb').write(d)
print(f"interp={len(open(interp,'rb').read()):#x} story_start={story_start:#x} image={len(d):#x}")
PY

"$BIN2TAP" "$OUT/image.bin" --start 0x500 --exec 0x500 -o "$OUT/image.tap"

# 30M cycles : depasse le splash (~15s) et laisse tourner le Z-code.
"$EMU" -r "$ROM" -f -n \
  --symbols "$OUT/ozmoo-oric.lab" \
  -t "$OUT/image.tap" \
  --type-keys 2600000:'CLOAD""\n' \
  --profile "$OUT/prof.txt" \
  --dump-ram-at 29000000:"$OUT/ram.bin" \
  --screenshot-text-at 29000000:"$OUT/screen.txt" \
  --cycles 30000000 || true

echo "=== ECRAN (texte du Z-code attendu) ==="
cat "$OUT/screen.txt" 2>/dev/null
