; EPIC 2 : deux lignes en adressage absolu ($BB80 = row0, $BBA8 = row1)
	* = $9000
	ldx #0
-	lda l1,x
	beq n2
	sta $bb80,x
	inx
	bne -
n2	ldx #0
-	lda l2,x
	beq fin
	sta $bba8,x       ; $BB80 + 40 = row1
	inx
	bne -
fin	jmp fin
l1	!text "LIGNE UN", 0
l2	!text "LIGNE DEUX", 0
