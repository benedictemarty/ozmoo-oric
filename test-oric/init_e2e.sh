#!/usr/bin/env bash
# Capture de la trace CPU du hang d'init (EPIC 5, v0.11.0).
# Build voie B (non-VMEM), interpreteur $500..$2eff pade, story czech.z3 a $2f00.
# Assemble avec labels VICE -> emulateur --symbols pour noms symboliques.
set -eu
cd "$(dirname "$0")/.."
EMU=~/Oric1/oric1-emu
BIN2TAP=~/Oric1/bin2tap
OUT=temp
mkdir -p "$OUT"

# --- 1. Templates minimaux (comme build-oric.sh) ---
FN="czech"; VS="Oric-0.1"
sed "s/@fn@/$FN/g" asm/file-name.tpl  > "$OUT/file-name.asm"
sed "s/@fn@/$FN/g" asm/walkthrough.tpl > "$OUT/walkthrough.asm"
sed -e 's/@0s@//g' -e 's/@1s@//g' -e 's/@2s@//g' -e 's/@3s@//g' -e "s#@date@#$(date +%d/%m/%Y)#g" \
    -e 's/@0c@/0/g' -e 's/@1c@/0/g' -e 's/@2c@/0/g' -e 's/@3c@/0/g' \
    -e "s/@vs@/$VS/g" asm/splashlines.tpl > "$OUT/splashlines.asm"

# --- 2. Assemblage non-VMEM + labels VICE ---
cd asm
acme --setpc 0x0500 \
  -DTARGET_ORIC=1 -DORIC_DEBUG_INIT=1 -DZ3=1 \
  -DCACHE_PAGES=4 -DSTACK_PAGES=4 -DCONF_TRK=1 \
  -DMAJOR_VERSION_NO=0 -DMINOR_VERSION_NO=1 \
  --cpu 6502 \
  --vicelabels ../$OUT/ozmoo-oric.lab \
  -o ../$OUT/interp.bin \
  ozmoo.asm
cd ..

# --- 3. Image = interp pade a $2f00 + story ---
python3 - "$OUT/interp.bin" test/czech.z3 "$OUT/image.bin" "$OUT/ozmoo-oric.lab" <<'PY'
import sys, re
interp, story, out, lab = sys.argv[1:5]
# story_start lu dynamiquement (bouge selon la taille de l'interpreteur)
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

# --- 4. .tap ---
"$BIN2TAP" "$OUT/image.bin" --start 0x500 --exec 0x500 -o "$OUT/image.tap"

# --- 5. Run E2E init (headless) : ROM BASIC + fast-load + CLOAD ---
#   30M cycles pour depasser l'attente splash (~15s emulees) ; on doit atteindre
#   les marqueurs ORIC_DEBUG_INIT '1'(avant deletable_init) '2'(deletable_init)
#   '3'(parse_object_table). Profil conserve pour diagnostic.
ROM=~/Oric1/roms/basic11b.rom
"$EMU" -r "$ROM" -f -n \
  --symbols "$OUT/ozmoo-oric.lab" \
  -t "$OUT/image.tap" \
  --type-keys 2600000:'CLOAD""\n' \
  --profile "$OUT/prof.txt" \
  --dump-ram-at 29000000:"$OUT/ram.bin" \
  --screenshot-text-at 29000000:"$OUT/screen.txt" \
  --cycles 30000000 || true

echo "=== ECRAN (markers 1/2/3 en haut a gauche) ==="
head -1 "$OUT/screen.txt" 2>/dev/null | cat -A

# --- 6. Assertion : l'init doit atteindre parse_object_table ('123') ---
if head -1 "$OUT/screen.txt" 2>/dev/null | grep -q '^123'; then
  echo "PASS: init complete (splash -> deletable_init -> parse_object_table)"
  exit 0
else
  echo "FAIL: init n'atteint pas les marqueurs 1/2/3"
  echo "--- top profil (adresse chaude = blocage) ---"; head -26 "$OUT/prof.txt" 2>/dev/null
  exit 1
fi
