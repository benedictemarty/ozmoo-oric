; Poke-test : $E000-$FFFF est-il de la RAM sous $0314=$80 (EPROM off) ?
; Meme condition que le runtime Ozmoo (read_track_sector ecrit $0314=$80, SEI).
; Pour chaque adresse : ecrit 2 motifs distincts et relit -> RAM si les 2 tiennent,
; ROM sinon. Controle $C000 (RAM deja prouvee). Resultat en $BB80 (ligne 0).
; Assemble a $9000, auto-run.
	* = $9000
	sei
	lda #$80
	sta $0314          ; drive0 side0, ROM BASIC off (b1=0), EPROM off (b7=1), IRQ off

	; --- ecrit le label statique ---
	ldx #0
-	lda label,x
	beq +
	sta $bb80,x
	inx
	bne -
+

	; --- teste chaque adresse ---
	lda #$00 : sta $10 : lda #$e0 : sta $11 : jsr testaddr : sta $bb85  ; E000
	lda #$00 : sta $10 : lda #$f0 : sta $11 : jsr testaddr : sta $bb8d  ; F000
	lda #$f0 : sta $10 : lda #$ff : sta $11 : jsr testaddr : sta $bb95  ; FFF0
	lda #$00 : sta $10 : lda #$c0 : sta $11 : jsr testaddr : sta $bb9d  ; C000 (controle)
	jmp *              ; garde l'ecran

; testaddr : pointeur ($10) -> A = 'R' (RAM) ou 'O' (ROM)
testaddr
	ldy #0
	lda #$5a
	sta ($10),y
	lda ($10),y
	cmp #$5a
	bne .rom
	lda #$a5
	sta ($10),y
	lda ($10),y
	cmp #$a5
	bne .rom
	lda #'R'
	rts
.rom
	lda #'O'
	rts

label
	!text "E000=?  F000=?  FFF0=?  C000=?", 0
