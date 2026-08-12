#!/usr/bin/env bash
# Build de sondage pour la cible ORIC (portage Ozmoo).
# Assemble le moteur avec ACME sans dependre de make.rb/exomizer/vice.
# But (EPIC 1) : faire progresser l'assemblage et lister les symboles a implementer.
set -u
cd "$(dirname "$0")/asm"

TMP=../temp
mkdir -p "$TMP"

# Fichiers normalement generes par make.rb (versions minimales pour le sondage) :
FN="hhgg"                       # nom de story-file (placeholder)
VS="Oric-0.1"                   # version affichee

# file-name.asm / walkthrough.asm : substitution @fn@
sed "s/@fn@/$FN/g" file-name.tpl  > "$TMP/file-name.asm"
sed "s/@fn@/$FN/g" walkthrough.tpl > "$TMP/walkthrough.asm"

# splashlines.asm : neutralise les placeholders texte (@Ns@) et couleur (@Nc@),
# et la version (@vs@).
sed -e 's/@0s@//g' -e 's/@1s@//g' -e 's/@2s@//g' -e 's/@3s@//g' \
    -e 's/@0c@/0/g' -e 's/@1c@/0/g' -e 's/@2c@/0/g' -e 's/@3c@/0/g' \
    -e "s/@vs@/$VS/g" \
    splashlines.tpl > "$TMP/splashlines.asm"

# Defines requis (valeurs par defaut make.rb) :
acme \
  --setpc 0x0500 \
  -DTARGET_ORIC=1 \
  -DZ3=1 \
  -DVMEM=1 \
  -DCACHE_PAGES=4 \
  -DSTACK_PAGES=4 \
  -DCONF_TRK=1 \
  -DMAJOR_VERSION_NO=0 \
  -DMINOR_VERSION_NO=1 \
  --cpu 6502 \
  -o "$TMP/ozmoo-oric.bin" \
  ozmoo.asm
