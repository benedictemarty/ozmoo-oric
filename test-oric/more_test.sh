#!/usr/bin/env bash
# Test PROMPT [MORE] Oric : quand un ecran se remplit, Ozmoo attend une touche.
# La version generique (screen.asm) affichait un "*" inverse CLIGNOTANT via la
# colour-map -> ABSENTE sur Oric (COLOUR_ADDRESS=SCREEN_ADDRESS, reg_background
# =$0000) => coin illisible/parasite. Le portage affiche desormais "-ESPACE-"
# en video inverse en bas d'ecran (oric_more_prompt, screenkernal-oric.asm).
# On fait tourner czech.z3 (sortie longue -> pagination fiable) SANS envoyer de
# touche : un prompt [MORE] doit etre affiche. Assertion : "-ESPACE-" a l'ecran.
# NB : le bloc inverse ($80|c) est lisible en --screenshot-text (bit7 masque).
set -eu
cd "$(dirname "$0")/.."
EMU=~/Oric1/oric1-emu
BIN2TAP=~/Oric1/bin2tap
ROM=~/Oric1/roms/basic11b.rom
OUT=temp
mkdir -p "$OUT"

FN="czech"; VS="Oric-0.1"
sed "s/@fn@/$FN/g" asm/file-name.tpl   > "$OUT/file-name.asm"
sed "s/@fn@/$FN/g" asm/walkthrough.tpl > "$OUT/walkthrough.asm"
sed -e 's/@0s@//g' -e 's/@1s@//g' -e 's/@2s@//g' -e 's/@3s@//g' -e "s#@date@#$(date +%d/%m/%Y)#g" \
    -e 's/@0c@/0/g' -e 's/@1c@/0/g' -e 's/@2c@/0/g' -e 's/@3c@/0/g' \
    -e "s/@vs@/$VS/g" asm/splashlines.tpl > "$OUT/splashlines.asm"

cd asm
acme --setpc 0x0500 -DTARGET_ORIC=1 -DZ3=1 \
  -DCACHE_PAGES=4 -DSTACK_PAGES=4 -DCONF_TRK=1 \
  -DMAJOR_VERSION_NO=0 -DMINOR_VERSION_NO=1 \
  --cpu 6502 --vicelabels ../$OUT/ozmoo-oric.lab -o ../$OUT/interp.bin ozmoo.asm
cd ..

python3 - "$OUT/interp.bin" test/czech.z3 "$OUT/image.bin" "$OUT/ozmoo-oric.lab" <<'PY'
import sys, re
interp, story, out, lab = sys.argv[1:5]
ss=int(re.search(r'al C:([0-9a-fA-F]+)\s+\.story_start',open(lab).read()).group(1),16)
d=open(interp,'rb').read(); d+=b'\x00'*(ss-0x500-len(d))+open(story,'rb').read()
open(out,'wb').write(d)
PY
"$BIN2TAP" "$OUT/image.bin" --start 0x500 --exec 0x500 -o "$OUT/image.tap" >/dev/null

# czech s'execute et remplit l'ecran -> prompt [MORE]. AUCUNE touche envoyee
# (a part le CLOAD) : le prompt doit rester affiche.
"$EMU" -r "$ROM" -f -n -t "$OUT/image.tap" \
  --type-keys 2600000:'CLOAD""\n' \
  --screenshot-text-at 40000000:"$OUT/more.txt" --cycles 42000000 >/dev/null 2>&1 || true

echo "=== derniere ligne ecran (@40M) ==="; grep -n '[^ ]' "$OUT/more.txt" | tail -1
if grep -q "ESPACE" "$OUT/more.txt" 2>/dev/null; then
  echo "PASS: prompt [MORE] Oric affiche '-ESPACE-' (lisible, video inverse)"
  exit 0
else
  echo "FAIL: indicateur [MORE] '-ESPACE-' absent a l'ecran"
  grep -n '[^ ]' "$OUT/more.txt" 2>/dev/null | tail -6
  exit 1
fi
