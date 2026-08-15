; Valide write_track_sector (écriture WD1793 $A0) : écrit un motif connu sur un
; secteur, le relit avec read_track_sector, et compare. Affiche 'P' si l'aller-retour
; est identique, 'F' + index sinon. Disque de travail formaté monté en drive A.
	* = $9000
	sei
	; motif source en $6000 : octet i = i EOR $5A (distinctif, non trivial)
	ldx #0
-	txa
	eor #$5a
	sta $6000,x
	inx
	bne -
	; écrit $6000 -> piste 5, secteur 0-based 0
	lda #$00 : sta readblocks_mempos : lda #$60 : sta readblocks_mempos+1
	lda #5 : ldx #0 : jsr write_track_sector
	; relit piste 5 secteur 0 -> $6100
	lda #$00 : sta readblocks_mempos : lda #$61 : sta readblocks_mempos+1
	lda #5 : ldx #0 : jsr read_track_sector
	; compare
	ldx #0
-	lda $6000,x
	cmp $6100,x
	bne .fail
	inx
	bne -
	lda #'P' : sta $bb80          ; PASS
	jmp .end
.fail
	lda #'F' : sta $bb80
	txa : clc : adc #$30 : sta $bb81   ; index (approx) du 1er écart
.end
	jmp .end

readblocks_mempos = $04
	!source "../asm/disk-oric.asm"
