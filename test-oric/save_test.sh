#!/usr/bin/env bash
# Valide le round-trip @save/@restore Oric (oric_save_game/oric_restore_game) EN CONTEXTE
# MOTEUR via -DORIC_SAVE_SELFTEST : jeu chargé -> mémorise un octet de dynmem, save (écrit
# l'état en secteurs bruts pistes hautes face 1), corrompt dynmem, restore (relit), vérifie
# la restauration. 'P' en $BB80 si OK. Prouve la sérialisation save/restore sur disque.
set -eu
cd "$(dirname "$0")/.."
EMU=~/Oric1/oric1-emu; ROM=~/Oric1/roms/basic11b.rom; MICRODISC=~/Oric1/roms/microdis.rom
MASTER=~/Oric1/disks/SEDO40u.DSK
STORY=${1:-test/czech.z3}
OUT=temp/save; mkdir -p "$OUT"
[ -x "$EMU" ] || { echo "reconstruire ~/Oric1"; exit 2; }

ZV=$(python3 -c "print(open('$STORY','rb').read(1)[0])")
sed "s/@fn@/czech/g" asm/file-name.tpl  > temp/file-name.asm
sed "s/@fn@/czech/g" asm/walkthrough.tpl > temp/walkthrough.asm
sed -e 's/@0s@//g;s/@1s@//g;s/@2s@//g;s/@3s@//g;s/@0c@/0/g;s/@1c@/0/g;s/@2c@/0/g;s/@3c@/0/g;s/@vs@/Oric-0.1/g' -e "s#@date@#$(date +%d/%m/%Y)#g" \
    asm/splashlines.tpl > temp/splashlines.asm

( cd asm && acme --setpc 0x0500 -DTARGET_ORIC=1 -DZ${ZV}=1 -DVMEM=1 -DORIC_SAVE_SELFTEST=1 \
  -DCACHE_PAGES=4 -DSTACK_PAGES=4 -DCONF_TRK=15 -DMAJOR_VERSION_NO=0 -DMINOR_VERSION_NO=1 \
  --cpu 6502 -o ../"$OUT"/st.bin ozmoo.asm ) 2>&1 | grep -i error && { echo FAIL asm; exit 1; } || true
python3 tools/build_game_disk.py "$MASTER" "$OUT/st.bin" "$STORY" "$OUT/st.dsk" OZMOO deadbeef 15 >/dev/null
"$EMU" -r "$ROM" --disk-rom "$MICRODISC" -d "$OUT/st.dsk" -n \
  --dump-ram-at 90000000:"$OUT/m.ram" --cycles 92000000 >/dev/null 2>&1 || true

res=$(python3 -c "d=open('$OUT/m.ram','rb').read(); print(chr(d[0xbb80]) if 32<=d[0xbb80]<127 else '.')")
echo "resultat self-test save/restore : '$res' (P=round-trip OK)"
if [ "$res" = "P" ]; then
  echo "PASS: @save/@restore Oric -- save->corrupt->restore reverte l'etat (serialisation disque OK)"
  exit 0
else
  echo "FAIL: save/restore round-trip incorrect"; exit 1
fi
