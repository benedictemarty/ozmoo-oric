#!/usr/bin/env bash
# Test de non-regression : interaction s_printchar (non-bufferise) + s_scroll_oric sur
# la DERNIERE ligne. Une longue chaine sans CR imprimee caractere par caractere doit
# hard-wrapper a la colonne 40 et scroller PROPREMENT (chaque bloc de 40 sur une ligne
# successive), SANS chevauchement. Garde le fix v0.36.1 (s_scroll_oric borne) et le
# chemin unbuffered utilise quand un jeu met is_buffered_window=0 (ex. tips PunyInform).
#
# La chaine de 110 chars distinctifs (scroll_unbuf.asm) doit donner exactement :
#   0123456789ABCDEFGHIJabcdefghij0123456789   (40)
#   KLMNOPQRSTklmnopqrst0123456789UVWXYZ0189   (40)
#   uvwxyz01890123456789PQRSTUVWXY             (30)
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
EMU="$HOME/Oric1/oric1-emu"; ROM="$HOME/Oric1/roms/basic11b.rom"; BIN2TAP="$HOME/Oric1/bin2tap"
[ -x "$EMU" ] || { echo "SKIP: emulateur absent"; exit 0; }
cd "$HERE"
acme --cpu 6502 -f plain -o scroll_unbuf.bin scroll_unbuf.asm 2>/dev/null || { echo "FAIL: assemblage"; exit 1; }
"$BIN2TAP" scroll_unbuf.bin --start 0x9000 --exec 0x9000 -o scroll_unbuf.tap --name TEST >/dev/null 2>&1
out=/tmp/scroll_unbuf.screen.txt
"$EMU" -r "$ROM" -t scroll_unbuf.tap -f -n --type-keys 2600000:'CLOAD""\n' \
  --screenshot-text-at 8500000:"$out" --cycles 9000000 >/dev/null 2>&1

ok=1
grep -qF "0123456789ABCDEFGHIJabcdefghij0123456789" "$out" || { echo "FAIL: ligne 1 (chevauchement scroll?)"; ok=0; }
grep -qF "KLMNOPQRSTklmnopqrst0123456789UVWXYZ0189" "$out" || { echo "FAIL: ligne 2 (chevauchement scroll?)"; ok=0; }
grep -qF "uvwxyz01890123456789PQRSTUVWXY"           "$out" || { echo "FAIL: ligne 3 (chevauchement scroll?)"; ok=0; }
if [ "$ok" = 1 ]; then
  echo "PASS: unbuffered + s_scroll_oric propre (110 chars sur 3 lignes, sans chevauchement)"
  exit 0
else
  echo "Ecran obtenu :"; sed -n '24,28p' "$out"; exit 1
fi
