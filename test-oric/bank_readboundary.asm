; Teste si read_track_sector perd des octets a la frontiere de page quand la
; destination est dans la zone banked $C000+ (hypothese du bug banking V5 : page
; $C300 = 18 octets $00 en tete). Lit 2 secteurs consecutifs (bloc 512 o) en
; $C200/$C300 (banked) + un controle en $6000 (RAM basse). Disque a motif non-nul
; byte[i]=(i+1)&$FF -> $C300 doit valoir 1,2,3,... Dump RAM ensuite pour comparer.
	* = $9000
	sei
	; secteur 0-based 0 -> $C200
	lda #$00 : sta readblocks_mempos : lda #$c2 : sta readblocks_mempos+1
	lda #1 : ldx #0 : jsr read_track_sector
	; secteur 0-based 1 -> $C300 (2e page du bloc, la ou apparaissent les 18 zeros)
	lda #$00 : sta readblocks_mempos : lda #$c3 : sta readblocks_mempos+1
	lda #1 : ldx #1 : jsr read_track_sector
	; CONTROLE : meme secteur 1 -> $6000 (RAM basse, hors zone banked)
	lda #$00 : sta readblocks_mempos : lda #$60 : sta readblocks_mempos+1
	lda #1 : ldx #1 : jsr read_track_sector
	; force overlay RAM visible pour le dump ($C000-$DFFF = RAM)
	lda #$80 : sta $0314
	; marqueur de fin a l'ecran
	lda #$aa : sta $bb80
fin	jmp fin

readblocks_mempos = $04
	!source "../asm/disk-oric.asm"
