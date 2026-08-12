#!/usr/bin/env bash
# Harnais de test EPIC 2+ : assemble un .asm 6502, le lance dans Phosphoric
# (headless, chargement tape via CLOAD + fast-load), capture l'ecran texte
# ($BB80) et verifie qu'il contient la chaine attendue.
#
# Usage : run-test.sh <fichier.asm> <exec_hex> "<chaine attendue>"
#   ex.  : run-test.sh screen_hello.asm 9000 "HELLO ORIC"
#
# Pre-requis : acme dans le PATH ; emulateur+ROMs dans ~/Oric1.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
EMU="$HOME/Oric1/oric1-emu"
ROM="$HOME/Oric1/roms/basic11b.rom"
BIN2TAP="$HOME/Oric1/bin2tap"

ASM="$1"; EXEC="$2"; EXPECT="$3"
base="${ASM%.asm}"
bin="$HERE/$base.bin"; tap="$HERE/$base.tap"; out="/tmp/$base.screen.txt"

cd "$HERE"   # pour que les !source "../asm/..." se resolvent
acme --cpu 6502 -f plain -o "$bin" "$ASM" || { echo "FAIL: assemblage"; exit 1; }
"$BIN2TAP" "$bin" --start "0x$EXEC" --exec "0x$EXEC" -o "$tap" --name TEST >/dev/null || {
	echo "FAIL: bin2tap"; exit 1; }

"$EMU" -r "$ROM" -t "$tap" -f -n \
	--type-keys 2600000:'CLOAD""\n' \
	--screenshot-text-at 8500000:"$out" --cycles 9000000 >/dev/null 2>&1

if grep -qF "$EXPECT" "$out"; then
	echo "PASS: \"$EXPECT\" present a l'ecran"
	exit 0
else
	echo "FAIL: \"$EXPECT\" absent. Ecran obtenu :"
	sed -n '1,4p' "$out"
	exit 1
fi
