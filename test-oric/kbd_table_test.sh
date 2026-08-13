#!/usr/bin/env bash
# Test de non-regression de la table clavier Oric (krc_to_ascii, keyboard-oric.asm).
# Pour chaque touche injectee via --type-keys, read_key (harnais kbd_read.asm, lecture
# brute affichee en $BB80) doit renvoyer l'ASCII attendu. Couvre les classes requises
# par la saisie ligne @sread : chiffres, lettres, espace, RETURN (13), DELETE (8).
set -eu
cd "$(dirname "$0")"
EMU=~/Oric1/oric1-emu
ROM=~/Oric1/roms/basic11b.rom
BIN2TAP=~/Oric1/bin2tap
OUT=../temp
mkdir -p "$OUT"

acme --setpc 0x9000 --cpu 6502 -o "$OUT/kbd_read.bin" kbd_read.asm
"$BIN2TAP" "$OUT/kbd_read.bin" --start 0x9000 --exec 0x9000 -o "$OUT/kbd_read.tap" >/dev/null

# "sequence --type-keys" : "hex_attendu" (RETURN=\n, DELETE=\b)
declare -A CASES=(
  ['1']=31 ['5']=35 ['0']=30 ['9']=39
  ['a']=61 ['n']=6e ['z']=7a ['s']=73 ['w']=77 ['e']=65 ['t']=74 ['l']=6c ['o']=6f
  [' ']=20 ['.']=2e ['/']=2f
  ['\n']=0d ['\b']=08
)
fail=0
for seq in "${!CASES[@]}"; do
  exp=${CASES[$seq]}
  "$EMU" -r "$ROM" -f -n -t "$OUT/kbd_read.tap" \
    --type-keys 2600000:'CLOAD""\n' --type-keys 12000000:"$seq" \
    --dump-ram-at 12500000:"$OUT/kbt.bin" --cycles 13000000 >/dev/null 2>&1 || true
  got=$(python3 -c "print('%02x' % open('$OUT/kbt.bin','rb').read()[0xbb80])")
  label=$(printf '%s' "$seq" | sed 's/\\n/RET/; s/\\b/DEL/')
  if [ "$got" = "$exp" ]; then
    echo "  ok  '$label' -> \$$got"
  else
    echo "  FAIL '$label' -> \$$got (attendu \$$exp)"; fail=1
  fi
done

if [ "$fail" = 0 ]; then
  echo "PASS: table clavier Oric complete (chiffres, lettres, espace, RETURN=13, DEL=8)"
  exit 0
else
  echo "FAIL: table clavier incomplete/incorrecte"
  exit 1
fi
