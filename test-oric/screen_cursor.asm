; [RESOLU] Ancien test curseur. Le bug n'etait PAS un conflit page-zero mais
; un oubli de preservation du registre X (setline ecrasait X, index de chaine de
; l'appelant). Voir asm/screenkernal-oric.asm pour la version correcte et testee.
; Germe de screenkernal-oric.asm. Affiche deux lignes via le curseur.
	* = $9000
col = $f0
row = $f1
ptr = $f2          ; 2 octets

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

; --- o_chrout : imprime A au curseur, gere CR (#13) et wrap 40 colonnes ------
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

; --- setline : ptr = $BB80 + row*40 -----------------------------------------
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
