#!/usr/bin/env bash
# Tranche l'hypothese : sous $0314=$80 (EPROM off, cond. runtime Ozmoo), la zone
# $E000-$FFFF est-elle de la RAM exploitable pour etendre le banking a 16 Ko ?
# Attendu si RAM : "E000=R  F000=R  FFF0=R  C000=R". C000 = controle RAM connue.
set -eu
cd "$(dirname "$0")"
EMU=~/Oric1/oric1-emu
BIN2TAP=~/Oric1/bin2tap
ROM=~/Oric1/roms/basic11b.rom
DROM=~/Oric1/roms/microdis.rom
OUT=../temp
mkdir -p "$OUT"

[ -x "$EMU" ] || { echo "reconstruire ~/Oric1 (make SDL2=0)"; exit 2; }
[ -x "$BIN2TAP" ] || { echo "reconstruire bin2tap (make tools dans ~/Oric1)"; exit 2; }

acme --cpu 6502 -f plain -o "$OUT/bank_e000.bin" bank_e000.asm || { echo "FAIL asm"; exit 1; }
"$BIN2TAP" "$OUT/bank_e000.bin" --start 0x9000 --exec 0x9000 -o "$OUT/bank_e000.tap" --name TEST >/dev/null

# Condition FIDELE au runtime Ozmoo : Microdisc + boot Sedoric (SEDO40u.DSK), puis le
# ML est injecte (-f) et pose $0314=$80. Screenshot apres stabilisation (~15M cycles).
SEDO=~/Oric1/disks/SEDO40u.DSK
"$EMU" -r "$ROM" --disk-rom "$DROM" -d "$SEDO" -t "$OUT/bank_e000.tap" -f \
  --screenshot-text-at 15000000:"$OUT/bank_e000.txt" --cycles 15500000 >/dev/null 2>&1

line="$(head -1 "$OUT/bank_e000.txt")"
echo "ligne 0 : '$line'"
e=$(echo "$line" | cut -c6); f=$(echo "$line" | cut -c14); v=$(echo "$line" | cut -c22); c=$(echo "$line" | cut -c30)
echo "E000=$e  F000=$f  FFF0=$v  C000=$c   (R=RAM, O=ROM)"
if [ "$c" != "R" ]; then echo "TEST INVALIDE : controle C000 != R (harnais/timing)"; exit 3; fi
if [ "$e" = "R" ] && [ "$f" = "R" ] && [ "$v" = "R" ]; then
  echo "RESULTAT : \$E000-\$FFFF EST de la RAM sous \$0314=\$80 -> banking 16 Ko possible"
  exit 0
else
  echo "RESULTAT : \$E000-\$FFFF n'est PAS pleinement RAM -> banking reste 8 Ko"
  exit 1
fi
