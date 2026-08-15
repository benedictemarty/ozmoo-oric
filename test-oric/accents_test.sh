#!/usr/bin/env bash
# Non-regression des ACCENTS FRANÇAIS (-DORIC_ACCENTS) : au boot, oric_load_accent_glyphs
# construit dans le charset $B400 les glyphes accentues (lettre de base + marque), et
# translate_zscii_to_petscii mappe les codes ZSCII accentues vers ces slots. Verifie :
# (1) slot 123 (é) = 'e' + accent aigu ; (2) slot 36 ($ -> ç) = 'c' + cedille ; (3) un
# code mappe apparait a l'ecran (jeu francais). Necessite un jeu FR (defaut aventure_fr).
set -eu
cd "$(dirname "$0")/.."
EMU=~/Oric1/oric1-emu; ROM=~/Oric1/roms/basic11b.rom; MICRODISC=~/Oric1/roms/microdis.rom
MASTER=~/Oric1/disks/SEDO40u.DSK
STORY=${1:-/home/bmarty/42/aventure_fr.z5}
OUT=temp/fr; mkdir -p "$OUT"
[ -x "$EMU" ] || { echo "reconstruire ~/Oric1"; exit 2; }
[ -f "$STORY" ] || { echo "jeu FR absent: $STORY (skip)"; exit 0; }

ZV=$(python3 -c "print(open('$STORY','rb').read(1)[0])")
sed "s/@fn@/czech/g" asm/file-name.tpl  > temp/file-name.asm
sed "s/@fn@/czech/g" asm/walkthrough.tpl > temp/walkthrough.asm
sed -e 's/@0s@//g;s/@1s@//g;s/@2s@//g;s/@3s@//g;s/@0c@/0/g;s/@1c@/0/g;s/@2c@/0/g;s/@3c@/0/g;s/@vs@/Oric-0.1/g' \
    asm/splashlines.tpl > temp/splashlines.asm

( cd asm && acme --setpc 0x0500 -DTARGET_ORIC=1 -DORIC_BANKING=1 -DZ${ZV}=1 -DVMEM=1 -DORIC_ACCENTS=1 \
  -DCACHE_PAGES=4 -DSTACK_PAGES=4 -DCONF_TRK=15 -DMAJOR_VERSION_NO=0 -DMINOR_VERSION_NO=1 \
  --cpu 6502 -o ../"$OUT"/at.bin ozmoo.asm ) 2>&1 | grep -i error && { echo FAIL asm; exit 1; } || true
python3 tools/build_game_disk.py "$MASTER" "$OUT/at.bin" "$STORY" "$OUT/at.dsk" OZMOO deadbeef 15 >/dev/null
"$EMU" -r "$ROM" --disk-rom "$MICRODISC" -d "$OUT/at.dsk" -n \
  --type-keys 40000000:' ' --type-keys 70000000:' ' \
  --dump-ram-at 88000000:"$OUT/at.ram" --screenshot-text-at 90000000:"$OUT/at.txt" --cycles 93000000 >/dev/null 2>&1 || true

python3 - "$OUT/at.ram" "$OUT/at.txt" <<'PY'
import sys
d=open(sys.argv[1],'rb').read(); scr=open(sys.argv[2]).read()
def gl(code): return [d[0xB400+code*8+r]&0x3F for r in range(8)]
e_acute=gl(123)   # é : accent (rangees 0-1 non nulles) + corps 'e'
c_ced=gl(36)      # ç : corps 'c' + cedille (rangee 7 non nulle)
ok_e = (e_acute[0]!=0 or e_acute[1]!=0) and e_acute[4]!=0   # accent present + barre du e
ok_c = c_ced[7]!=0 and c_ced[2]!=0                          # cedille + haut du c
# un code reaffecte doit apparaitre a l'ecran (jeu FR affiche des accents)
mapped=set("{}~`\\^[]_@#$%&")
seen=any(ch in mapped for ch in scr)
print(f"slot123(é): accent+e={ok_e}  slot36(ç): c+cedille={ok_c}  code accentue a l'ecran={seen}")
ok = ok_e and ok_c and seen
print("PASS: accents FR construits dans le charset ET rendus a l'ecran" if ok else "FAIL: accents absents")
sys.exit(0 if ok else 1)
PY