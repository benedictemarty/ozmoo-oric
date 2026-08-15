; Valide le support FACE 1 de read_track_sector (SEUIL : piste >= TRACKS_PER_SIDE
; = face 1, comme le n° linéaire que produit readblock). Disque 80 pistes/face,
; chaque secteur byte0 = '0'+face. On lit la piste 3 (face 0) et la piste 83 (=80+3,
; face 1 physique 3) -> doit afficher "01" (si le seuil échouait, on lirait "00").
	* = $9000
	sei
	lda #$00 : sta readblocks_mempos : lda #$60 : sta readblocks_mempos+1  ; dest $6000
	; face 0, piste 3, secteur 0-based 0
	lda #3 : ldx #0 : jsr read_track_sector
	lda $6000 : sta $bb80          ; attendu '0'
	; face 1 : piste linéaire 83 = TRACKS_PER_SIDE(80)+3, secteur 0
	lda #83 : ldx #0 : jsr read_track_sector
	lda $6000 : sta $bb81          ; attendu '1'
fin	jmp fin

readblocks_mempos = $04
	!source "../asm/disk-oric.asm"
