	* = $9000
	sei
	lda #<$bb80
	sta readblocks_mempos
	lda #>$bb80
	sta readblocks_mempos + 1
	lda #2            ; piste
	ldx #3            ; secteur
	ldy #0            ; device
	jsr read_track_sector
fin	jmp fin

readblocks_mempos = $10   ; pointeur ZP (fourni par constants-oric en integration)
	!source "../asm/disk-oric.asm"
