#!/usr/bin/env bash
# Valide read_track_sector FACE 1 (bit 7 de la piste). Disque à marqueur de face
# (byte0 = '0'+face), lecture piste 3 des 2 faces -> attendu "01".
set -eu
cd "$(dirname "$0")"
EMU=~/Oric1/oric1-emu; BIN2TAP=~/Oric1/bin2tap
ROM=~/Oric1/roms/basic11b.rom; DROM=~/Oric1/roms/microdis.rom
OUT=../temp; mkdir -p "$OUT"
[ -x "$EMU" ] || { echo "reconstruire ~/Oric1"; exit 2; }

# disque : byte0 = ord('0')+side, byte1 = track (side-major 2x42x17x256)
python3 - "$OUT/side.raw" <<'PY'
import sys
SIDES,TRACKS,SECTORS,SECSZ=2,42,17,256
raw=bytearray()
for side in range(SIDES):
    for t in range(TRACKS):
        for si in range(SECTORS):
            b=bytearray(SECSZ); b[0]=ord('0')+side; b[1]=t&0xff; raw+=b
open(sys.argv[1],'wb').write(raw)
PY
python3 ~/Oric1/tools/dsk_raw2mfm.py "$OUT/side.raw" "$OUT/side.dsk" sidemajor 2 42 17 >/dev/null

acme --cpu 6502 -f plain -o "$OUT/rts_side1.bin" rts_side1.asm 2>&1 | grep -i error && { echo FAIL asm; exit 1; } || true
"$BIN2TAP" "$OUT/rts_side1.bin" --start 0x9000 --exec 0x9000 -o "$OUT/rts_side1.tap" --name TEST >/dev/null
"$EMU" -r "$ROM" --disk-rom "$DROM" -d "$OUT/side.dsk" -t "$OUT/rts_side1.tap" -f -n \
  --type-keys 2600000:'CLOAD""\n' --screenshot-text-at 8500000:"$OUT/side.txt" --cycles 9000000 >/dev/null 2>&1

got="$(head -1 "$OUT/side.txt" | cut -c1-2)"
echo "2 premiers caracteres : '$got' (attendu '01')"
if [ "$got" = "01" ]; then
  echo "PASS: read_track_sector selectionne bien la face 1 (bit 7 de la piste)"
  exit 0
else
  echo "FAIL: face 1 non selectionnee (lu '$got')"; head -1 "$OUT/side.txt" | cat -A; exit 1
fi
