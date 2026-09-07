#!/usr/bin/env bash
# Test COULEUR "dans les espaces" (opt-in -DORIC_COLOUR). @set_colour Z-machine ->
# encre Oric, posee sur un ESPACE existant (colonne convertie en octet d'attribut,
# affiche comme un blanc) => AUCUN decalage du texte. Cf. colour_buffer_char +
# ink_buffer[] (screenkernal-oric.asm) et la boucle de blit (screen.asm).
# Jeu de test coltest.z5 (source coltest.inf) : "avant [rouge]ROUGE[blanc] apres".
# Assertion sur la RAM ecran : l'espace avant ROUGE = $01 (encre rouge), ROUGE suit
# SANS decalage ; l'espace avant "apres" = $07 (encre blanche).
set -eu
cd "$(dirname "$0")/.."
EMU=~/Oric1/oric1-emu; BIN2TAP=~/Oric1/bin2tap; OUT=temp
STORY=test-oric/coltest.z5
[ -f "$STORY" ] || { echo "SKIP: coltest.z5 absent"; exit 0; }
# (re)compile si inform6 present
command -v inform6 >/dev/null && inform6 -v5 test-oric/coltest.inf "$STORY" >/dev/null 2>&1 || true

FN=coltest
sed "s/@fn@/$FN/g" asm/file-name.tpl  > "$OUT/file-name.asm"
sed "s/@fn@/$FN/g" asm/walkthrough.tpl > "$OUT/walkthrough.asm"
sed -e 's/@0s@//g' -e 's/@1s@//g' -e 's/@2s@//g' -e 's/@3s@//g' -e "s#@date@#$(date +%d/%m/%Y)#g" -e 's/@0c@/0/g' -e 's/@1c@/0/g' \
    -e 's/@2c@/0/g' -e 's/@3c@/0/g' -e "s/@vs@/x/g" asm/splashlines.tpl > "$OUT/splashlines.asm"
cd asm
acme --setpc 0x0500 -DTARGET_ORIC=1 -DZ5=1 -DORIC_COLOUR=1 -DCACHE_PAGES=4 -DSTACK_PAGES=4 -DCONF_TRK=1 \
  -DMAJOR_VERSION_NO=0 -DMINOR_VERSION_NO=1 --cpu 6502 --vicelabels ../$OUT/col.lab -o ../$OUT/col.bin ozmoo.asm >/dev/null 2>&1
cd ..
python3 - $OUT/col.bin "$STORY" $OUT/col_img.bin $OUT/col.lab <<'PY'
import sys,re
i,s,o,l=sys.argv[1:5]
ss=int(re.search(r'al C:([0-9a-fA-F]+)\s+\.story_start',open(l).read()).group(1),16)
d=open(i,'rb').read(); d+=b'\x00'*(ss-0x500-len(d))+open(s,'rb').read(); open(o,'wb').write(d)
PY
"$BIN2TAP" $OUT/col_img.bin --start 0x500 --exec 0x500 -o $OUT/col.tap >/dev/null
"$EMU" -m atmos -r ~/Oric1/roms/basic11b.rom -f -n -t $OUT/col.tap \
  --type-keys "2600000:CLOAD\"\"\n" --dump-ram-at 40000000:$OUT/col_scr.bin --cycles 42000000 >/dev/null 2>&1
python3 - "$OUT/col_scr.bin" <<'PY'
import sys
scr=open(sys.argv[1],'rb').read()[0xBB80:0xBB80+40]
def txt(a,b): return bytes(scr[a:b]).decode('latin1')
ok=True
def chk(cond,msg):
    global ok
    print(("OK  " if cond else "FAIL")+": "+msg); ok=ok and cond
chk(txt(0,5)=="avant",        f'"avant" en col0-4 (={txt(0,5)!r})')
chk(scr[5]==0x01,             f'encre ROUGE $01 sur l\'espace col5 (={scr[5]:#04x})')
chk(txt(6,11)=="ROUGE",       f'"ROUGE" en col6-10 SANS decalage (={txt(6,11)!r})')
chk(scr[11]==0x07,            f'encre BLANC $07 sur l\'espace col11 (={scr[11]:#04x})')
chk(txt(12,17)=="apres",      f'"apres" en col12-16 SANS decalage (={txt(12,17)!r})')
print("PASS: couleur posee sur les espaces, aucun decalage" if ok else "FAIL: couleur incorrecte")
sys.exit(0 if ok else 1)
PY
