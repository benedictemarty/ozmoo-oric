#!/usr/bin/env bash
# Valide l'horloge jiffy VIA Timer 1 (saisie temporisee @read/@read_char). Configure T1
# free-run 60 Hz, polle le flag de debordement dans une double boucle (~0,9 s emule),
# compte les jiffys, affiche le compte hexa. Attendu ~60 Hz -> ~$30-$40 (48-64 dec).
set -eu
cd "$(dirname "$0")"
EMU=~/Oric1/oric1-emu; BIN2TAP=~/Oric1/bin2tap
ROM=~/Oric1/roms/basic11b.rom; DROM=~/Oric1/roms/microdis.rom
OUT=../temp; mkdir -p "$OUT"
[ -x "$EMU" ] || { echo "reconstruire ~/Oric1"; exit 2; }

acme --cpu 6502 -f plain -o "$OUT/timer.bin" timer_test.asm 2>&1 | grep -i error && { echo FAIL asm; exit 1; } || true
"$BIN2TAP" "$OUT/timer.bin" --start 0x9000 --exec 0x9000 -o "$OUT/timer.tap" --name TEST >/dev/null
"$EMU" -r "$ROM" --disk-rom "$DROM" -t "$OUT/timer.tap" -f -n \
  --type-keys 2600000:'CLOAD""\n' --screenshot-text-at 6000000:"$OUT/timer.txt" --cycles 6500000 >/dev/null 2>&1

hex="$(head -1 "$OUT/timer.txt" | cut -c1-2)"
dec=$((16#$hex))
echo "jiffys comptes (~0,9 s de poll) : \$$hex = $dec dec (attendu 40-70 pour ~60 Hz)"
if [ "$dec" -ge 40 ] && [ "$dec" -le 70 ]; then
  echo "PASS: horloge jiffy VIA Timer 1 ~60 Hz OK (saisie temporisee fonctionnelle)"
  exit 0
else
  echo "FAIL: cadence horloge hors plage"; exit 1
fi
