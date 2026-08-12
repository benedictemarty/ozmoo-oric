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
sed -e 's/@0s@//g' -e 's/@1s@//g' -e 's/@2s@//g' -e 's/@3s@//g' \
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
python3 - "$OUT/interp.bin" test/czech.z3 "$OUT/image.bin" <<'PY'
import sys
interp, story, out = sys.argv[1], sys.argv[2], sys.argv[3]
d = open(interp,'rb').read()
pad_to = 0x2f00 - 0x500          # taille interpreteur cible
assert len(d) <= pad_to, f"interp {len(d):#x} > {pad_to:#x}"
d = d + b'\x00'*(pad_to - len(d))
d += open(story,'rb').read()
open(out,'wb').write(d)
print(f"interp={len(open(interp,'rb').read()):#x} pad_to={pad_to:#x} image={len(d):#x}")
PY

# --- 4. .tap ---
"$BIN2TAP" "$OUT/image.bin" --start 0x500 --exec 0x500 -o "$OUT/image.tap"

# --- 5. Run profilé (headless) : ROM BASIC + fast-load + CLOAD ---
#   Le hang est une boucle infinie -> le profiler fait ressortir l'adresse chaude.
ROM=~/Oric1/roms/basic11b.rom
"$EMU" -r "$ROM" -f -n \
  --symbols "$OUT/ozmoo-oric.lab" \
  -t "$OUT/image.tap" \
  --type-keys 2600000:'CLOAD""\n' \
  --profile "$OUT/prof.txt" \
  --dump-ram-at 13000000:"$OUT/ram.bin" \
  --screenshot-text-at 13000000:"$OUT/screen.txt" \
  --cycles 14000000 || true

echo "=== ECRAN FINAL (markers 1/2/3 en haut a gauche) ==="
head -3 "$OUT/screen.txt" 2>/dev/null
echo "=== TOP DU PROFIL (adresses chaudes = la boucle) ==="
head -30 "$OUT/prof.txt" 2>/dev/null
