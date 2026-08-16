; Valide le bip AY-3-8912 : programme le PSG (via VIA + handshake PCR) pour jouer une
; tonalité canal A (R0 période, R7 mixer tonalité A, R8 volume 15), attend, puis coupe
; (R8=0). --psg-trace de l'émulateur doit montrer les écritures R7/R8. 'B' en $BB80.
	* = $9000
	sei
	lda #$ff : sta $0303        ; VIA DDRA = sortie (bus PSG)
	; R0 = période (aigu)
	lda #0 : ldx #$60 : jsr .psgw
	; R1 = 0
	lda #1 : ldx #0   : jsr .psgw
	; R7 = $7e : tonalité A ON, IOA sortie
	lda #7 : ldx #$7e : jsr .psgw
	; R8 = 15 : volume canal A
	lda #8 : ldx #$0f : jsr .psgw
	; attente ~courte
	ldy #0
-	dey : bne -
	; R8 = 0 : silence
	lda #8 : ldx #0 : jsr .psgw
	lda #'B' : sta $bb80
.end	jmp .end

; écrit le registre PSG A avec la valeur X (handshake VIA PCR $030C)
.psgw
	sta $0301         ; port A = numéro de registre
	ldy #$ee : sty $030c    ; BDIR+BC1 : latch adresse
	ldy #$cc : sty $030c    ; inactif
	stx $0301         ; port A = valeur
	ldy #$ec : sty $030c    ; BDIR : écrit la donnée
	ldy #$cc : sty $030c    ; inactif
	rts
