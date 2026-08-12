; Test screenkernal-oric : ecrit 30 CR puis "SCROLL OK".
; Sans scroll, la 31e ligne serait hors ecran ; avec scroll, "SCROLL OK"
; apparait en bas -> sa presence prouve que le defilement fonctionne.
	* = $9000
	sei
	jsr oric_init
	ldx #0
loop	lda msg,x
	beq done
	jsr oric_chrout
	inx
	bne loop
done	jmp done

msg
	; 30 retours-ligne
	!byte 13,13,13,13,13,13,13,13,13,13
	!byte 13,13,13,13,13,13,13,13,13,13
	!byte 13,13,13,13,13,13,13,13,13,13
	!text "SCROLL OK", 0

	!source "../asm/screenkernal-oric.asm"
