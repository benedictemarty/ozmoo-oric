	* = $9000
	sei
	lda #$80
	sta $12
	lda #$bb
	sta $13          ; ptr=$BB80
	lda #0
	sta $10          ; col
	ldx #0
loop	lda msg,x
	beq end
	jsr putc
	inx
	bne loop
end	jmp end
putc
	ldy $10
	sta ($12),y
	inc $10
	rts
msg	!text "ABCDEF", 0
