; Test diagnostic : primitive o_chrout avec ZP relocalisee en $10-$13
	* = $9000
col = $10
row = $11
ptr = $12          ; 2 octets ($12/$13)
start
	sei
	lda #0
	sta col
	sta row
	jsr setline
	ldx #0
loop
	lda msg,x
	beq end
	jsr o_chrout
	inx
	bne loop
end
	jmp end
o_chrout
	cmp #13
	beq wrapline
	ldy col
	sta (ptr),y
	inc col
	lda col
	cmp #40
	bcc oc_done
wrapline
	lda #0
	sta col
	inc row
	jsr setline
oc_done
	rts
setline
	lda #<$bb80
	sta ptr
	lda #>$bb80
	sta ptr+1
	ldx row
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
	rts
msg	!text "LIGNE UN", 13, "LIGNE DEUX", 0
