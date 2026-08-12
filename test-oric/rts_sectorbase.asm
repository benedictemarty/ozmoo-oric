; Test : valide la base de numérotation des secteurs de read_track_sector.
; Disque known.dsk : secteur physique d'ID k contient octet0 = k (1..17).
; read_track_sector reçoit un secteur 0-based (comme readblock) et ajoute +1
; -> lire secteur 0 doit donner octet0=1, secteur 1 -> 2, secteur 2 -> 3.
; Affiche ces 3 octets (en ASCII '1','2','3' attendus) en haut d'écran.
	* = $9000
	sei
	; destination de lecture -> $6000
	lda #$00 : sta readblocks_mempos
	lda #$60 : sta readblocks_mempos+1
	; --- secteur 0-based = 0 -> attend octet0 = 1 ---
	lda #1                 ; piste 1
	ldx #0                 ; secteur 0-based
	jsr read_track_sector
	lda $6000              ; octet0 lu (= ID physique = 1)
	clc : adc #$30         ; -> ASCII
	sta $bb80
	; --- secteur 1 -> attend 2 ---
	lda #1 : ldx #1 : jsr read_track_sector
	lda $6000 : clc : adc #$30 : sta $bb81
	; --- secteur 2 -> attend 3 ---
	lda #1 : ldx #2 : jsr read_track_sector
	lda $6000 : clc : adc #$30 : sta $bb82
fin	jmp fin

readblocks_mempos = $04    ; pointeur ZP (2 o) attendu par read_track_sector
	!source "../asm/disk-oric.asm"
