	* = $9000
	sei
	lda #$80
	sta $12
	lda #$bb
	sta $13          ; ptr = $BB80
	ldy #0
	lda #65          ; 'A'
	sta ($12),y
	iny
	lda #66          ; 'B'
	sta ($12),y
loop	jmp loop
