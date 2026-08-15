#!/usr/bin/env bash
# Valide write_track_sector (ecriture WD1793 $A0) par aller-retour : ecrit un motif
# sur piste 5 sec 0, relit, compare -> ecran 'P' si identique. Disque de travail formate.
set -eu
cd "$(dirname "$0")"
EMU=~/Oric1/oric1-emu; BIN2TAP=~/Oric1/bin2tap
ROM=~/Oric1/roms/basic11b.rom; DROM=~/Oric1/roms/microdis.rom
OUT=../temp; mkdir -p "$OUT"
[ -x "$EMU" ] || { echo "reconstruire ~/Oric1"; exit 2; }

# disque formate (secteurs presents), contenu initial nul -> MFM Oric
python3 - "$OUT/scratch.raw" <<'PY'
import sys
open(sys.argv[1],'wb').write(bytes(2*42*17*256))   # 2 faces x 42 x 17 x 256, zeros
PY
python3 ~/Oric1/tools/dsk_raw2mfm.py "$OUT/scratch.raw" "$OUT/scratch.dsk" sidemajor 2 42 17 >/dev/null

acme --cpu 6502 -f plain -o "$OUT/rts_write.bin" rts_write.asm 2>&1 | grep -i error && { echo FAIL asm; exit 1; } || true
"$BIN2TAP" "$OUT/rts_write.bin" --start 0x9000 --exec 0x9000 -o "$OUT/rts_write.tap" --name TEST >/dev/null
"$EMU" -r "$ROM" --disk-rom "$DROM" -d "$OUT/scratch.dsk" -t "$OUT/rts_write.tap" -f -n \
  --type-keys 2600000:'CLOAD""\n' --screenshot-text-at 8500000:"$OUT/rw.txt" --cycles 9000000 >/dev/null 2>&1

got="$(head -1 "$OUT/rw.txt" | cut -c1-2)"
echo "resultat ecran : '$got' (attendu 'P')"
if [ "${got:0:1}" = "P" ]; then
  echo "PASS: write_track_sector -> aller-retour ecriture/lecture identique (256 o)"
  exit 0
else
  echo "FAIL: ecriture/relecture differente ('$got')"; exit 1
fi
