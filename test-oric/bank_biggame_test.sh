#!/usr/bin/env bash
# Non-regression du support GROS JEU V5 (v0.36.6) : la piste de config passe a
# CONFIG_SECTORS=4 secteurs (1024 o) -> Aventyr.z5 (133K, config 519 o > 512) se
# construit ET boote en VMEM banking. Verifie : build OK, intro visible, pas de
# [Not supported]. Necessite examples/Aventyr.z5.
set -eu
cd "$(dirname "$0")/.."
EMU=~/Oric1/oric1-emu; ROM=~/Oric1/roms/basic11b.rom; MICRODISC=~/Oric1/roms/microdis.rom
MASTER=~/Oric1/disks/SEDO40u.DSK
STORY=${1:-examples/Aventyr.z5}
OUT=temp/biggame; mkdir -p "$OUT"
[ -x "$EMU" ] || { echo "reconstruire ~/Oric1"; exit 2; }
[ -f "$STORY" ] || { echo "jeu absent: $STORY"; exit 2; }

sed "s/@fn@/czech/g" asm/file-name.tpl  > temp/file-name.asm
sed "s/@fn@/czech/g" asm/walkthrough.tpl > temp/walkthrough.asm
sed -e 's/@0s@//g;s/@1s@//g;s/@2s@//g;s/@3s@//g;s/@0c@/0/g;s/@1c@/0/g;s/@2c@/0/g;s/@3c@/0/g;s/@vs@/Oric-0.1/g' \
    asm/splashlines.tpl > temp/splashlines.asm

( cd asm && acme --setpc 0x0500 -DTARGET_ORIC=1 -DORIC_BANKING=1 -DZ5=1 -DVMEM=1 \
  -DCACHE_PAGES=4 -DSTACK_PAGES=4 -DCONF_TRK=15 -DMAJOR_VERSION_NO=0 -DMINOR_VERSION_NO=1 \
  --cpu 6502 -o ../"$OUT"/interp.bin ozmoo.asm ) 2>&1 | grep -i error && { echo "FAIL asm"; exit 1; } || true
# build disque : DOIT reussir (config 519 o tient dans 4 secteurs = 1024 o)
python3 tools/build_game_disk.py "$MASTER" "$OUT/interp.bin" "$STORY" "$OUT/game.dsk" OZMOO deadbeef 15 >/dev/null \
  || { echo "FAIL build_game_disk (config trop grande ?)"; exit 1; }

KEYS="--type-keys 50000000:' ' --type-keys 80000000:' ' --type-keys 105000000:' '"
"$EMU" -r "$ROM" --disk-rom "$MICRODISC" -d "$OUT/game.dsk" -n \
  $KEYS --screenshot-text-at 112000000:"$OUT/s.txt" --cycles 115000000 >/dev/null 2>&1 || true

ns=$(grep -ci 'not supported' "$OUT/s.txt" 2>/dev/null; true)
# intro visible = texte de jeu au-dela du splash (mots FR/EN/SV du Colossal Cave)
intro=$(grep -ciE 'v[Aa]g|byggnad|road|building|slutet|adventure' "$OUT/s.txt" 2>/dev/null; true)
echo "[Not supported]=$ns (attendu 0)  intro_visible=$intro (>=1)"
if [ "$ns" = "0" ] && [ "$intro" -ge 1 ]; then
  echo "PASS: gros jeu V5 (${STORY##*/}, 133K) construit et boote en VMEM banking (config 4 secteurs)"
  exit 0
else
  echo "FAIL: regression support gros jeu"; sed -n '1,10p' "$OUT/s.txt"; exit 1
fi
