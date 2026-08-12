; Scan matrice clavier Oric. ay_write preserve X (col) et Y (row).
	* = $9000
	sei
	lda $0302
	ora #$07
	and #$f7
	sta $0302          ; DDRB : PB0-2 sortie, PB3 entree
	lda #7
	sta ay_reg
	lda #$ff
	sta ay_val
	jsr ay_write       ; R7 = $FF (bit6=1 : port A entree)
scan
	ldx #0             ; colonne
colL
	lda $0300
	and #$f8
	sta tmp
	txa
	ora tmp
	sta $0300          ; ORB : colonne
	ldy #0             ; ligne
rowL
	lda rowmask,y
	sta ay_val
	lda #14
	sta ay_reg
	jsr ay_write       ; R14 = ~(1<<row) ; preserve X,Y
	lda $0300
	and #$08           ; PB3 ?
	bne found
	iny
	cpy #8
	bne rowL
	inx
	cpx #8
	bne colL
	jmp scan
found
	txa
	ora #$30
	sta $bb81          ; colonne
	tya
	ora #$30
	sta $bb82          ; ligne
	lda #$4b
	sta $bb80          ; 'K'
fin	jmp fin

; ay_write : ecrit ay_val dans le registre ay_reg (preserve A,X,Y)
ay_write
	pha
	txa
	pha
	tya
	pha
	lda ay_reg
	sta $0301
	lda #$ee
	sta $030c
	lda #$cc
	sta $030c
	lda ay_val
	sta $0301
	lda #$ec
	sta $030c
	lda #$cc
	sta $030c
	pla
	tay
	pla
	tax
	pla
	rts

rowmask !byte $fe,$fd,$fb,$f7,$ef,$df,$bf,$7f
ay_reg  !byte 0
ay_val  !byte 0
tmp     !byte 0
