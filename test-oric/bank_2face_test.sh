#!/usr/bin/env bash
# Non-regression du support 2-FACES + V8 (v0.37.0) : un gros jeu V8 (Jigsaw, 298K)
# deborde la face 0 -> build_game_disk place les blocs restants sur la FACE 1, et
# read_track_sector les lit (seuil piste lineaire >= TRACKS_PER_SIDE). PREUVE :
# un bloc VMEM de la face 1 doit etre resident en RAM et IDENTIQUE a la story.
# Necessite un gros V8 debordant la face 0 (defaut /home/bmarty/42/jigsaw.z8).
set -eu
cd "$(dirname "$0")/.."
EMU=~/Oric1/oric1-emu; ROM=~/Oric1/roms/basic11b.rom; MICRODISC=~/Oric1/roms/microdis.rom
MASTER=~/Oric1/disks/SEDO40u.DSK
STORY=${1:-/home/bmarty/42/jigsaw.z8}
OUT=temp/2face; mkdir -p "$OUT"
[ -x "$EMU" ] || { echo "reconstruire ~/Oric1"; exit 2; }
[ -f "$STORY" ] || { echo "gros jeu V8 absent: $STORY (skip)"; exit 0; }

ZV=$(python3 -c "print(open('$STORY','rb').read(1)[0])")
sed "s/@fn@/czech/g" asm/file-name.tpl  > temp/file-name.asm
sed "s/@fn@/czech/g" asm/walkthrough.tpl > temp/walkthrough.asm
sed -e 's/@0s@//g;s/@1s@//g;s/@2s@//g;s/@3s@//g;s/@0c@/0/g;s/@1c@/0/g;s/@2c@/0/g;s/@3c@/0/g;s/@vs@/Oric-0.1/g' -e "s#@date@#$(date +%d/%m/%Y)#g" \
    asm/splashlines.tpl > temp/splashlines.asm

( cd asm && acme --setpc 0x0500 -DTARGET_ORIC=1 -DORIC_BANKING=1 -DZ${ZV}=1 -DVMEM=1 \
  -DCACHE_PAGES=4 -DSTACK_PAGES=4 -DCONF_TRK=15 -DMAJOR_VERSION_NO=0 -DMINOR_VERSION_NO=1 \
  --cpu 6502 --vicelabels ../"$OUT"/t.lab -o ../"$OUT"/t.bin ozmoo.asm ) 2>&1 | grep -i error && { echo FAIL asm; exit 1; } || true
out=$(python3 tools/build_game_disk.py "$MASTER" "$OUT/t.bin" "$STORY" "$OUT/t.dsk" OZMOO deadbeef 15 2>&1) || { echo "$out"; echo "FAIL build"; exit 1; }
echo "$out" | grep -i 'FACE 1' || { echo "FAIL: le jeu ne deborde pas sur la face 1 (choisir un plus gros)"; exit 1; }

# passe l'ecran-titre (espaces) + explore pour fauter des blocs hauts (face 1)
KEYS=""; for c in 92 96 100 104 108 112 116 120 124 128; do KEYS="$KEYS --type-keys ${c}000000:' '"; done
KEYS="$KEYS --type-keys 135000000:'about\n' --type-keys 150000000:'look\n'"
timeout 1000 "$EMU" -r "$ROM" --disk-rom "$MICRODISC" -d "$OUT/t.dsk" -n \
  $KEYS --dump-ram-at 155000000:"$OUT/t.ram" --screenshot-text-at 156000000:"$OUT/t.txt" --cycles 158000000 >/dev/null 2>&1 || true

ns=$(grep -ci 'not supported' "$OUT/t.txt" 2>/dev/null; true)
python3 - "$OUT/t.lab" "$OUT/t.ram" "$STORY" "$ns" <<'PY'
import re,sys,importlib.util
lab=open(sys.argv[1]).read(); d=open(sys.argv[2],'rb').read(); story=open(sys.argv[3],'rb').read(); ns=sys.argv[4]
def A(n):
    m=re.search(r'al C:([0-9a-f]{4}) \.'+re.escape(n)+r'\b',lab); return int(m.group(1),16) if m else None
def imp(name,path):
    s=importlib.util.spec_from_file_location(name,path); m=importlib.util.module_from_spec(s); s.loader.exec_module(m); return m
od=imp('od','tools/oric_disk.py'); bg=imp('bg','tools/build_game_disk.py'); mfm=imp('mfm2raw','tools/mfm2raw.py')
# Rejoue le placement pour connaitre l'ensemble EXACT des blocs VMEM sur la face 1.
sides,tracks,sectors,_=mfm.parse_mfm(open(sys.argv and '/home/bmarty/Oric1/disks/SEDO40u.DSK','rb').read(),17)
ns_p,dyn,tot=od.story_vmem_layout(story); static=story[ns_p*256:]; nblk=(len(static)+255)//256
auto=13568+ns_p*256; ndata=(auto+255)//256
FC,CC=(17-12)//2,(17-2)//2; ndesc=1 if ndata<=FC else 1+-(-(ndata-FC)//CC)
last=21+((ndesc+ndata)-1)//sectors; skip={20}|set(range(21,last+1))
geo=bg._geometry(tracks,sectors,first_track=15,config_sectors=od.CONFIG_SECTORS,skip_tracks=skip,total_tracks=2*tracks)
p=od.place_story(nblk,geo)
face1_vmem=set(dyn+n//2 for n,(t,s) in enumerate(p.blocks) if t>=tracks)  # blocs 512o sur face1
vfrp=d[A('vmap_first_ram_page')]; vmax=d[0x34]
found=[]
for i in range(vmax):
    zl=d[0xFE00+i]; zh=d[0xFE80+i]; blk=zl|((zh&0x03)<<8)
    page=vfrp+2*i
    if page>=0xB4: page+=0x0C
    if blk in face1_vmem:
        if d[page*256:page*256+512]==story[blk*512:blk*512+512]: found.append(blk)
print(f"[Not supported]={ns}  blocs FACE 1 residents ET identiques a la story : {sorted(set(found))}")
ok=(ns=="0") and len(found)>=1
print("PASS: 2-faces + V8 valides (bloc face-1 lu du disque == story)" if ok
      else "FAIL: aucun bloc face-1 correct resident (jeu trop court ? ou erreur)")
sys.exit(0 if ok else 1)
PY