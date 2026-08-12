	* = $9000
col = $10
ptr = $12
	sei
	lda #0
	sta col
	lda #0
	sta rownum
	jsr setline
	ldx #0
loop	lda msg,x
	beq end
	jsr o_chrout
	inx
	bne loop
end	jmp end
o_chrout
	cmp #13
	beq wrapline
	ldy col
	sta (ptr),y
	inc col
	rts
wrapline
	lda #0
	sta col
	inc rownum
	jsr setline
	rts
setline
	txa
	pha
	lda #$80
	sta ptr
	lda #$bb
	sta ptr+1
	ldx rownum
	beq sl_ok
sl_add
	clc
	lda ptr
	adc #40
	sta ptr
	bcc sl_nc
	inc ptr+1
sl_nc
	dex
	bne sl_add
sl_ok
	pla
	tax
	rts
rownum	!byte 0
msg	!text "ABC", 13, "DEF", 0
