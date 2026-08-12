; Test d'integration : appelle s_init + s_printchar (interface Ozmoo reelle).
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

msg	!text "HELLO VIA S_PRINTCHAR", 13, "SECOND LINE", 0

; --- equates ZP (fournies normalement par constants-oric.asm) ---------------
zp_screenline           = $d1
zp_screencolumn         = $d3
zp_screenrow            = $d6
s_colour                = $74
s_stored_x              = $b4
s_stored_y              = $b5
s_current_screenpos_row = $b6

	!source "../asm/screenkernal-oric.asm"
