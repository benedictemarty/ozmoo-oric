#!/usr/bin/env bash
# Non-regression du FIX banking V5 (v0.36.5) : en -DORIC_BANKING -DZ5, la routine
# print_line_from_buffer ne doit PLUS ecrire la RAM couleur (COLOURFUL_LOWER_WIN)
# sur Oric (NO_COLOUR_MAP) -> plus de corruption du bloc VMEM en $C300 -> advent V5
# jouable sans [Not supported]. Necessite un jeu V5 (defaut examples/advent_punyinform.z5).
set -eu
cd "$(dirname "$0")/.."
EMU=~/Oric1/oric1-emu; ROM=~/Oric1/roms/basic11b.rom; MICRODISC=~/Oric1/roms/microdis.rom
MASTER=~/Oric1/disks/SEDO40u.DSK
STORY=${1:-examples/advent_punyinform.z5}
OUT=temp/bankv5; mkdir -p "$OUT"
[ -x "$EMU" ] || { echo "reconstruire ~/Oric1"; exit 2; }
[ -f "$STORY" ] || { echo "jeu V5 absent: $STORY"; exit 2; }

# templates splash (comme vmem_disk_run)
sed "s/@fn@/czech/g" asm/file-name.tpl  > temp/file-name.asm
sed "s/@fn@/czech/g" asm/walkthrough.tpl > temp/walkthrough.asm
sed -e 's/@0s@//g;s/@1s@//g;s/@2s@//g;s/@3s@//g;s/@0c@/0/g;s/@1c@/0/g;s/@2c@/0/g;s/@3c@/0/g;s/@vs@/Oric-0.1/g' \
    asm/splashlines.tpl > temp/splashlines.asm

( cd asm && acme --setpc 0x0500 -DTARGET_ORIC=1 -DORIC_BANKING=1 -DZ5=1 -DVMEM=1 \
  -DCACHE_PAGES=4 -DSTACK_PAGES=4 -DCONF_TRK=15 -DMAJOR_VERSION_NO=0 -DMINOR_VERSION_NO=1 \
  --cpu 6502 -o ../"$OUT"/interp.bin ozmoo.asm ) 2>&1 | grep -i error && { echo "FAIL asm"; exit 1; } || true
python3 tools/build_game_disk.py "$MASTER" "$OUT/interp.bin" "$STORY" "$OUT/game.dsk" OZMOO deadbeef 15 >/dev/null

KEYS="--type-keys 40000000:' ' --type-keys 70000000:' '"
"$EMU" -r "$ROM" --disk-rom "$MICRODISC" -d "$OUT/game.dsk" -n \
  $KEYS --dump-ram-at 80000000:"$OUT/c300.ram" \
  --screenshot-text-at 85000000:"$OUT/s85.txt" --cycles 88000000 >/dev/null 2>&1 || true

ns=$(grep -ci 'not supported' "$OUT/s85.txt" 2>/dev/null; true)
intro=$(grep -ciE 'adventure|road|building' "$OUT/s85.txt" 2>/dev/null; true)
z=$(python3 -c "d=open('$OUT/c300.ram','rb').read(); print(next((i for i,b in enumerate(d[0xc300:0xc400]) if b!=0),256))")
echo "[Not supported]=$ns (attendu 0)  intro_visible=$intro (>=1)  \$C300 zeros_tete=$z (attendu 0)"
if [ "$ns" = "0" ] && [ "$intro" -ge 1 ] && [ "$z" = "0" ]; then
  echo "PASS: banking V5 sans corruption \$C300, advent V5 jouable"
  exit 0
else
  echo "FAIL: regression banking V5"; sed -n '1,8p' "$OUT/s85.txt"; exit 1
fi
