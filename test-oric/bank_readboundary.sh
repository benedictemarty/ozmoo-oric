#!/usr/bin/env bash
# Prouve que read_track_sector ne perd PAS d'octets a la frontiere de page quand la
# destination est en zone banked $C000+ (hypothese du bug banking V5 refutee).
# Disque a motif entierement non-nul byte[i]=(i+1)&$FF ; lit un bloc 512 o dans
# $C200/$C300 + controle $6000. Attendu : $C300 = 01 02 03 ... (aucun zero perdu).
set -eu
cd "$(dirname "$0")/.."
EMU=~/Oric1/oric1-emu; ROM=~/Oric1/roms/basic11b.rom; DROM=~/Oric1/roms/microdis.rom
OUT=temp/bankdiag; mkdir -p "$OUT"
[ -x "$EMU" ] || { echo "reconstruire ~/Oric1 (make SDL2=0)"; exit 2; }

python3 - "$OUT/pat.raw" <<'PY'
import sys
SIDES,TRACKS,SECTORS,SECSZ=2,42,17,256
raw=bytearray()
for _s in range(SIDES):
    for _t in range(TRACKS):
        for _si in range(SECTORS):
            raw += bytes(((i+1)&0xFF) for i in range(SECSZ))
open(sys.argv[1],'wb').write(raw)
PY
python3 ~/Oric1/tools/dsk_raw2mfm.py "$OUT/pat.raw" "$OUT/pat.dsk" sidemajor 2 42 17 >/dev/null
( cd test-oric && acme --cpu 6502 -f plain -o "../$OUT/brb.bin" bank_readboundary.asm ) 2>&1 | grep -i error || true
~/Oric1/bin2tap "$OUT/brb.bin" --start 0x9000 --exec 0x9000 -o "$OUT/brb.tap" --name TEST >/dev/null
"$EMU" -r "$ROM" --disk-rom "$DROM" -d "$OUT/pat.dsk" -t "$OUT/brb.tap" -f -n \
  --type-keys 2600000:'CLOAD""\n' --dump-ram-at 8000000:"$OUT/brb.ram" --cycles 8500000 >/dev/null 2>&1

python3 - "$OUT/brb.ram" <<'PY'
import sys
d=open(sys.argv[1],'rb').read()
c3=d[0xc300:0xc318]; ctl=d[0x6000:0x6018]
exp=bytes(((i+1)&0xFF) for i in range(24))
print('$C300[0:24] :', ' '.join('%02x'%b for b in c3))
print('$6000[0:24] :', ' '.join('%02x'%b for b in ctl))
ok = (c3==exp and ctl==exp and d[0xbb80]==0xaa)
print('PASS: lecture banked propre (aucun octet perdu a la frontiere $C300)' if ok
      else 'FAIL: octets perdus/incoherents en zone banked')
sys.exit(0 if ok else 1)
PY