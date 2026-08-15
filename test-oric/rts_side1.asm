; Valide le support FACE 1 de read_track_sector (bit 7 de la piste = face 1).
; Disque : chaque secteur a byte0 = '0'+face ('0' face 0, '1' face 1). On lit la
; piste 3 secteur 0 sur les DEUX faces -> doit afficher "01" (si la face n'etait
; pas selectionnee, on lirait "00").
	* = $9000
	sei
	lda #$00 : sta readblocks_mempos : lda #$60 : sta readblocks_mempos+1  ; dest $6000
	; face 0, piste 3, secteur 0-based 0
	lda #3 : ldx #0 : jsr read_track_sector
	lda $6000 : sta $bb80          ; attendu '0'
	; face 1 : piste 3 avec bit7 = $83, secteur 0
	lda #$83 : ldx #0 : jsr read_track_sector
	lda $6000 : sta $bb81          ; attendu '1'
fin	jmp fin

readblocks_mempos = $04
	!source "../asm/disk-oric.asm"
