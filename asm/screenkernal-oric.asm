; =============================================================================
; screenkernal-oric.asm — primitives d'affichage ORIC (portage Ozmoo)
; -----------------------------------------------------------------------------
; Couche bas-niveau ecran TEXT Oric ($BB80, 40x28, codes ASCII, attributs serie).
; Register-safe : oric_chrout preserve X et Y (A = caractere en entree).
; Modele valide empiriquement sur Phosphoric (voir docs/PORTING_ORIC.md, EPIC 2).
;
; NB : primitives autonomes et testees. Le branchement sur les points d'entree
; attendus par Ozmoo (kernal_printchar, etc.) sera fait dans un incrementt ulterieur.
; =============================================================================

SCR_BASE  = $bb80
SCR_COLS  = 40
SCR_ROWS  = 28
SCR_LAST  = SCR_BASE + SCR_COLS * (SCR_ROWS - 1)   ; $bfb8, debut derniere ligne

o_ptr     = $12          ; pointeur ecran indirect (2 octets ZP)

; --- oric_init : curseur en haut-gauche, ecran efface -----------------------
oric_init
	lda #0
	sta o_col
	sta o_row
	jsr oric_cls
	jsr o_setline
	rts

; --- oric_cls : remplit l'ecran d'espaces (1120 octets) ---------------------
oric_cls
	lda #$20
	ldx #0
oc_l1	sta $bb80,x
	sta $bc80,x
	sta $bd80,x
	sta $be80,x
	inx
	bne oc_l1
	ldx #96
oc_l2	sta $bf80-1,x      ; $bf80..$bfdf (96 octets)
	dex
	bne oc_l2
	rts

; --- oric_chrout : imprime A ; gere CR (#13), wrap 40 col, scroll -----------
; Register-safe : X et Y restaures en sortie.
oric_chrout
	stx o_savex
	sty o_savey
	cmp #13
	beq o_newline
	ldy o_col
	sta (o_ptr),y
	inc o_col
	lda o_col
	cmp #SCR_COLS
	bcc o_exit
o_newline
	lda #0
	sta o_col
	inc o_row
	lda o_row
	cmp #SCR_ROWS
	bcc o_reline
	; depassement bas -> reste sur la derniere ligne et fait defiler
	dec o_row
	jsr oric_scroll
o_reline
	jsr o_setline
o_exit
	ldx o_savex
	ldy o_savey
	rts

; --- o_setline : o_ptr = SCR_BASE + o_row*40 (preserve X) -------------------
o_setline
	txa
	pha
	lda #<SCR_BASE
	sta o_ptr
	lda #>SCR_BASE
	sta o_ptr+1
	ldx o_row
	beq sl_ok
sl_add
	clc
	lda o_ptr
	adc #SCR_COLS
	sta o_ptr
	bcc sl_nc
	inc o_ptr+1
sl_nc
	dex
	bne sl_add
sl_ok
	pla
	tax
	rts

; --- oric_scroll : remonte les lignes 1..27 vers 0..26, efface la ligne 27 --
oric_scroll
	ldx #0
os_l1	lda $bba8,x        ; ligne1.. -> ligne0..  (1024 premiers octets)
	sta $bb80,x
	lda $bba8+256,x
	sta $bb80+256,x
	lda $bba8+512,x
	sta $bb80+512,x
	lda $bba8+768,x
	sta $bb80+768,x
	inx
	bne os_l1
	ldx #0
os_l2	lda $bba8+1024,x   ; 56 octets restants ($bfa8..$bfdf -> $bf80..$bfb7)
	sta $bb80+1024,x
	inx
	cpx #56
	bne os_l2
	lda #$20            ; efface la derniere ligne ($bfb8..$bfdf, 40 octets)
	ldx #SCR_COLS
os_l3	sta SCR_LAST-1,x
	dex
	bne os_l3
	rts

; --- variables d'etat (memoire absolue, hors page zero) ---------------------
o_col	!byte 0
o_row	!byte 0
o_savex	!byte 0
o_savey	!byte 0
