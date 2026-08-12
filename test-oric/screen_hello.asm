; Test EPIC 2 : ecrire "HELLO ORIC" en $BB80 (modele ecran valide)
; Assemble a $9000, auto-run.
	* = $9000
	ldx #0
-	lda text,x
	beq done
	sta $bb80,x      ; ecran TEXT Oric, ligne 0
	inx
	bne -
done
	jmp done         ; boucle infinie (garde l'ecran)
text
	!text "HELLO ORIC", 0
