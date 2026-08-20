#!/usr/bin/env bash
# Test CURSEUR DE SAISIE Oric : au prompt @sread, un bloc video-inverse ($A0 =
# espace inverse) doit etre dessine a la position de saisie (turn_on_cursor), et
# SUIVRE la frappe (update_cursor apres l'echo). Avant, les routines curseur
# etaient des stubs (rts) -> aucun repere de saisie : l'utilisateur tapait "a
# l'aveugle" (symptome "Ozmoo n'a pas de zone de saisie"). Cf. screenkernal-oric.asm.
#
# Le bloc $A0 est INVISIBLE dans --screenshot-text (masque bit7) : on inspecte donc
# la RAM ecran ($BB80, 40x28) via --dump-ram-at. On joue HHGG (V3, intro courte ->
# prompt fiable ~74M). Fichier commercial NON versionne ; SKIP si absent.
set -eu
cd "$(dirname "$0")/.."
EMU=~/Oric1/oric1-emu
ROM=~/Oric1/roms/basic11b.rom
MICRODISC=~/Oric1/roms/microdis.rom
MASTER=~/Oric1/disks/SEDO40u.DSK
STORY=${1:-/home/bmarty/42/hhgg_r59.dat}
OUT=temp/vmem
mkdir -p "$OUT"
[ -f "$STORY" ] || { echo "SKIP: fichier jeu absent : $STORY"; exit 0; }

ZVER=$(python3 -c "import sys;print(open(sys.argv[1],'rb').read(1)[0])" "$STORY")
FN="hhgg"; VS="Oric-0.1"
sed "s/@fn@/$FN/g" asm/file-name.tpl   > "temp/file-name.asm"
sed "s/@fn@/$FN/g" asm/walkthrough.tpl > "temp/walkthrough.asm"
sed -e 's/@0s@//g' -e 's/@1s@//g' -e 's/@2s@//g' -e 's/@3s@//g' \
    -e 's/@0c@/0/g' -e 's/@1c@/0/g' -e 's/@2c@/0/g' -e 's/@3c@/0/g' \
    -e "s/@vs@/$VS/g" asm/splashlines.tpl > "temp/splashlines.asm"

cd asm
acme --setpc 0x0500 -DTARGET_ORIC=1 -DZ${ZVER}=1 -DVMEM=1 \
  -DCACHE_PAGES=4 -DSTACK_PAGES=4 -DCONF_TRK=15 -DMAJOR_VERSION_NO=0 -DMINOR_VERSION_NO=1 \
  --cpu 6502 -o ../"$OUT"/hhgg_interp.bin ozmoo.asm
cd ..
python3 tools/build_game_disk.py "$MASTER" "$OUT/hhgg_interp.bin" "$STORY" \
  "$OUT/hhgg.dsk" HHGG cafedeed 15 >/dev/null 2>&1

# Phase 1 : prompt inactif (~74M) -> bloc curseur juste apres ">".
# Phase 2 : on tape "x" (SANS Entree) a 76M -> l'echo 'x' apparait et le bloc suit.
"$EMU" -r "$ROM" --disk-rom "$MICRODISC" -d "$OUT/hhgg.dsk" -n \
  --dump-ram-at 74000000:"$OUT/cur_idle.bin" \
  --type-keys 76000000:'x' \
  --dump-ram-at 82000000:"$OUT/cur_typed.bin" \
  --cycles 84000000 >/dev/null 2>&1

python3 - "$OUT/cur_idle.bin" "$OUT/cur_typed.bin" <<'PY'
import sys
BASE=0xBB80; W=40; H=28; CUR=0xA0
def scr(f): d=open(f,'rb').read(); return d[BASE:BASE+W*H]
def prompt_row(s):
    # derniere ligne (hors ligne statut row 0) contenant '>'
    for r in range(H-1,0,-1):
        line=s[r*W:r*W+W]
        if 0x3E in line:  # '>'
            return r, line
    return None,None
def txt(line): return ''.join(chr(b&0x7f) if 32<=(b&0x7f)<127 else '.' for b in line)

ok=True
# --- Phase 1 : curseur au prompt inactif ---
s=scr(sys.argv[1]); r,line=prompt_row(s)
if r is None: print("FAIL: pas de prompt '>' trouve (phase 1)"); sys.exit(1)
gt=line.index(0x3E)                     # colonne du '>'
if line[gt+1]==CUR:
    print(f"OK phase1: bloc curseur $A0 en r{r} c{gt+1} (juste apres '>')  |{txt(line).rstrip()}|")
else:
    print(f"FAIL phase1: pas de bloc $A0 apres '>' (r{r} c{gt+1}={line[gt+1]:#04x})  |{txt(line).rstrip()}|"); ok=False

# --- Phase 2 : apres frappe 'x', echo + curseur avance d'une colonne ---
s2=scr(sys.argv[2]); r2,line2=prompt_row(s2)
gt2=line2.index(0x3E)
echoed=(line2[gt2+1]&0x7f)==ord('x')    # 'x' echote juste apres '>'
moved=line2[gt2+2]==CUR                  # bloc curseur en colonne suivante
if echoed and moved:
    print(f"OK phase2: '>x' echote + bloc curseur en c{gt2+2}  |{txt(line2).rstrip()}|")
else:
    print(f"FAIL phase2: echo={echoed} bloc_suit={moved}  |{txt(line2).rstrip()}|"); ok=False

if ok:
    print("PASS: curseur de saisie Oric visible au prompt ET suit la frappe")
    sys.exit(0)
sys.exit(1)
PY
