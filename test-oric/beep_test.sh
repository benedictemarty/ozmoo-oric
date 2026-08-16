#!/usr/bin/env bash
# Valide le bip AY-3-8912 (@sound_effect) : le test programme le PSG (R7 mixer, R8 volume)
# pour une tonalite canal A puis silence. --psg-trace doit montrer R8=0F (volume) puis R8=00.
set -eu
cd "$(dirname "$0")"
EMU=~/Oric1/oric1-emu; BIN2TAP=~/Oric1/bin2tap
ROM=~/Oric1/roms/basic11b.rom; DROM=~/Oric1/roms/microdis.rom
OUT=../temp; mkdir -p "$OUT"
[ -x "$EMU" ] || { echo "reconstruire ~/Oric1"; exit 2; }
acme --cpu 6502 -f plain -o "$OUT/beep.bin" beep_test.asm 2>&1 | grep -i error && { echo FAIL asm; exit 1; } || true
"$BIN2TAP" "$OUT/beep.bin" --start 0x9000 --exec 0x9000 -o "$OUT/beep.tap" --name TEST >/dev/null
"$EMU" -r "$ROM" --disk-rom "$DROM" -t "$OUT/beep.tap" -f -n \
  --type-keys 2600000:'CLOAD""\n' --psg-trace "$OUT/psg.log" \
  --screenshot-text-at 7000000:"$OUT/beep.txt" --cycles 7500000 >/dev/null 2>&1
b="$(head -1 "$OUT/beep.txt" | cut -c1)"
vol=$(grep -vE '^#' "$OUT/psg.log" | grep -cE 'R8=0F')
sil=$(grep -vE '^#' "$OUT/psg.log" | grep -cE 'R8=00')
echo "ecran='$b' (B attendu) ; R8=0F(volume) x$vol ; R8=00(silence) x$sil"
if [ "$b" = "B" ] && [ "$vol" -ge 1 ] && [ "$sil" -ge 1 ]; then
  echo "PASS: bip AY canal A (volume 15 -> 0) programme correctement"
  exit 0
else
  echo "FAIL: bip non programme"; exit 1
fi
