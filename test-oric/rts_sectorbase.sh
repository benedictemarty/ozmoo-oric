#!/usr/bin/env bash
# Valide la base de numérotation des secteurs de read_track_sector (voie A) :
# readblock produit un secteur 0-based, les ID physiques Sedoric/MFM sont 1-based
# (1..17), donc read_track_sector ajoute +1. Disque à contenu connu (octet0 = ID
# physique), lecture des secteurs 0/1/2 -> doit afficher '123'.
set -eu
cd "$(dirname "$0")"
EMU=~/Oric1/oric1-emu
BIN2TAP=~/Oric1/bin2tap
ROM=~/Oric1/roms/basic11b.rom
DROM=~/Oric1/roms/microdis.rom
OUT=../temp
mkdir -p "$OUT"

# 1) disque brut à contenu connu (octet0 = ID physique = si+1), puis MFM Oric
python3 - "$OUT/known.raw" <<'PY'
import sys
SIDES,TRACKS,SECTORS,SECSZ=2,42,17,256
raw=bytearray()
for side in range(SIDES):
    for track in range(TRACKS):
        for si in range(SECTORS):
            b=bytearray(SECSZ); b[0]=si+1; b[1]=track&0xff; raw+=b
open(sys.argv[1],'wb').write(raw)
PY
python3 ~/Oric1/tools/dsk_raw2mfm.py "$OUT/known.raw" "$OUT/known.dsk" sidemajor 2 42 17 >/dev/null

# 2) assemble + tape
acme --cpu 6502 -f plain -o "$OUT/rts_sectorbase.bin" rts_sectorbase.asm >/dev/null 2>&1 || { echo "FAIL asm"; exit 1; }
"$BIN2TAP" "$OUT/rts_sectorbase.bin" --start 0x9000 --exec 0x9000 -o "$OUT/rts_sectorbase.tap" --name TEST >/dev/null

# 3) run headless (ML via tape + disque connu en drive A)
"$EMU" -r "$ROM" --disk-rom "$DROM" -d "$OUT/known.dsk" -t "$OUT/rts_sectorbase.tap" -f -n \
  --type-keys 2600000:'CLOAD""\n' --screenshot-text-at 8500000:"$OUT/rts.txt" --cycles 9000000 >/dev/null 2>&1

got="$(head -1 "$OUT/rts.txt" | cut -c1-3)"
echo "3 premiers caracteres : '$got' (attendu '123')"
if [ "$got" = "123" ]; then
  echo "PASS: read_track_sector 0-based -> ID physique +1 (secteur base validee sur Oric)"
  exit 0
else
  echo "FAIL"; head -1 "$OUT/rts.txt" | cat -A; exit 1
fi
