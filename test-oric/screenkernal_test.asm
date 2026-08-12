; Test screenkernal-oric : ecrit 30 CR puis "SCROLL OK".
; Sans scroll, la 31e ligne serait hors ecran ; avec scroll, "SCROLL OK"
; apparait en bas -> sa presence prouve que le defilement fonctionne.
	* = $9000
	sei
	jsr s_init
	ldx #0
loop	lda msg,x
	beq done
	jsr s_printchar
	inx
	bne loop
done	jmp done

msg
	; 30 retours-ligne
	!byte 13,13,13,13,13,13,13,13,13,13
	!byte 13,13,13,13,13,13,13,13,13,13
	!byte 13,13,13,13,13,13,13,13,13,13
	!text "SCROLL OK", 0

zp_screenline = $d1
zp_screencolumn = $d3
zp_screenrow = $d6
s_colour = $74
s_stored_x = $b4
s_stored_y = $b5
s_current_screenpos_row = $b6
	!source "../asm/screenkernal-oric.asm"
