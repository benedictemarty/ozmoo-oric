	* = $9000
	sei
	lda #$80
	sta $0314          ; drive 0, side 0
	lda #$00
	sta $0310          ; Restore -> piste 0
	jsr fwait
	; Seek piste 2 : data reg = cible, commande Seek $10
	lda #2
	sta $0313          ; data = piste cible
	lda #$10
	sta $0310          ; Seek
	jsr fwait
	lda #3
	sta $0312          ; secteur 3
	lda #$80
	sta $0310          ; Read Sector
	ldy #0
rl	lda $0310
	and #$01
	beq rd
	lda $0310
	and #$02
	beq rl
	lda $0313
	sta $bb80,y
	iny
	bne rl
rd	jmp rd
fwait	ldx #$40
-	dex
	bne -
fw	lda $0310
	and #$01
	bne fw
	rts
