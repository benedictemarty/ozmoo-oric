; =============================================================================
; screenkernal-oric.asm — couche ecran ORIC pour Ozmoo (remplace screenkernal.asm)
; -----------------------------------------------------------------------------
; Fournit l'interface attendue par le moteur (screen.asm, text.asm, streams.asm) :
;   s_init, s_plot, s_printchar, s_set_text_colour, s_reset_scrolled_lines,
;   s_delete_cursor, s_erase_window, convert_petscii_to_screencode.
; Ecran TEXT Oric $BB80, 40x28, codes ASCII, register-safe.
; Les variables ZP (zp_screencolumn/row/line, s_colour, s_stored_x/y...) viennent
; de constants-oric.asm. Version simplifiee (fenetre unique, sans attributs) :
; premier objectif = afficher le texte du moteur. Fenetres/couleur : increments suivants.
; =============================================================================

SCR_BASE  = $bb80
SCR_LAST  = SCR_BASE + 40 * 27        ; $bfb8 : debut derniere ligne

!ifdef ORIC_LOG_CHARS {
oric_log_idx = $5f00                  ; DEBUG : index buffer log s_printchar
oric_log_buf = $6000                  ; DEBUG : buffer 256 octets (RAM libre)
}

; --- convert_petscii_to_screencode : sur Oric, ASCII = code ecran (identite
;     pour l'ASCII imprimable ; raffinement casse/ZSCII ulterieur) ------------
convert_petscii_to_screencode
	rts

; --- s_init : dimensions ecran + curseur en haut + effacement ---------------
s_init
	lda #0
!ifdef ORIC_LOG_CHARS {
	sta oric_log_idx
}
	sta zp_screencolumn
	sta zp_screenrow
	sta s_scrolled_lines
	; Zero s_ignore_next_linebreak (3 o) + s_reverse ($b0-$b3), comme screenkernal.asm.
	; CRUCIAL : s_reverse non initialise -> print_buffer2 rempli de $FF -> chaque
	; caractere bufferise ecrase en $FF par 'ora print_buffer2' (texte invisible).
	ldx #3
-	sta s_ignore_next_linebreak,x
	dex
	bpl -
	lda #$ff
	sta s_current_screenpos_row       ; force recalcul
	jsr s_cls_oric
	jsr s_setline
	rts

; --- s_plot : C=0 -> place curseur (X=ligne, Y=colonne) ; C=1 -> lit curseur -
s_plot
	bcc sp_set
	ldx zp_screenrow
	ldy zp_screencolumn
	rts
sp_set
	cpx s_screen_height
	bcc +
	ldx s_screen_height_minus_one
+	stx zp_screenrow
	sty zp_screencolumn
	jsr s_setline
	rts

; --- s_set_text_colour : A = couleur -> s_colour ----------------------------
s_set_text_colour
	sta s_colour
	rts

; --- s_reset_scrolled_lines -------------------------------------------------
s_reset_scrolled_lines
	pha
	lda #0
	sta s_scrolled_lines
	pla
	rts

; --- s_delete_cursor / s_erase_window : stubs (non appeles en pratique) ------
s_delete_cursor
s_erase_window
	rts

; --- s_printchar : CHROUT-like. A = caractere. Preserve X et Y. -------------
s_printchar
	stx s_stored_x
	sty s_stored_y
!ifdef ORIC_LOG_CHARS {
	; DEBUG : journalise chaque octet recu (X libre, restaure en fin). Buffer
	; 256 octets a $6000, index a $5f00 (init 0 dans s_init). Wrap = on lit page 1.
	ldx oric_log_idx
	sta oric_log_buf,x
	inc oric_log_idx
}
	cmp #$93                  ; PETSCII clear-screen (147) -> efface + home
	beq spc_clear
	cmp #$0d
	beq spc_newline
	cmp #$12                  ; reverse on (18)
	beq spc_rev_on
	cmp #$92                  ; reverse off (146)
	beq spc_rev_off
	; caractere imprimable
	ora s_reverse             ; bit 7 = inverse video sur Oric
	ldy zp_screencolumn
	sta (zp_screenline),y
	inc zp_screencolumn
	lda zp_screencolumn
	cmp s_screen_width
	bcc spc_done
spc_newline
	lda #0
	sta zp_screencolumn
	inc zp_screenrow
	lda zp_screenrow
	cmp s_screen_height
	bcc spc_reline
	dec zp_screenrow                  ; reste sur la derniere ligne
	jsr s_scroll_oric
spc_reline
	jsr s_setline
spc_done
	ldx s_stored_x
	ldy s_stored_y
	clc
	rts

; reverse on/off ($12/$92) : bit 7 des codes ecran = inverse video sur Oric
spc_rev_on
	lda #$80
	sta s_reverse
	jmp spc_done
spc_rev_off
	lda #0
	sta s_reverse
	jmp spc_done

; clear-screen ($93) : efface l'ecran, curseur en haut a gauche
spc_clear
	jsr s_cls_oric
	lda #0
	sta zp_screencolumn
	sta zp_screenrow
	jsr s_setline
	jmp spc_done

; --- s_setline : zp_screenline = SCR_BASE + zp_screenrow*40 (preserve X) -----
s_setline
	txa
	pha
	lda #<SCR_BASE
	sta zp_screenline
	lda #>SCR_BASE
	sta zp_screenline + 1
	ldx zp_screenrow
	beq ssl_ok
ssl_add
	clc
	lda zp_screenline
	adc #40
	sta zp_screenline
	bcc ssl_nc
	inc zp_screenline + 1
ssl_nc
	dex
	bne ssl_add
ssl_ok
	pla
	tax
	rts

; --- s_cls_oric : ecran rempli d'espaces (1120 octets) ----------------------
s_cls_oric
	lda #$20
	ldx #0
scl_1	sta $bb80,x
	sta $bc80,x
	sta $bd80,x
	sta $be80,x
	inx
	bne scl_1
	ldx #96
scl_2	sta $bf80-1,x
	dex
	bne scl_2
	rts

; --- s_scroll_oric : remonte lignes 1..27 -> 0..26, efface ligne 27 ---------
s_scroll_oric
	ldx #0
sso_1	lda $bba8,x
	sta $bb80,x
	lda $bba8+256,x
	sta $bb80+256,x
	lda $bba8+512,x
	sta $bb80+512,x
	lda $bba8+768,x
	sta $bb80+768,x
	inx
	bne sso_1
	ldx #0
sso_2	lda $bba8+1024,x
	sta $bb80+1024,x
	inx
	cpx #56
	bne sso_2
	lda #$20
	ldx #40
sso_3	sta SCR_LAST-1,x
	dex
	bne sso_3
	rts

; --- routines de support (stubs pour premier affichage ; a etoffer) ---------
; Curseur materiel : non necessaire pour le premier affichage.
update_cursor
turn_on_cursor
turn_off_cursor
toggle_darkmode
	rts

; Efface la ligne courante (espaces sur la ligne du curseur).
s_erase_line
	txa
	pha
	tya
	pha
	jsr s_setline
	lda #$20
	ldy #0
sel_l	sta (zp_screenline),y
	iny
	cpy s_screen_width
	bne sel_l
	pla
	tay
	pla
	tax
	rts

; --- variables couleur / mode (stubs) ---------------------------------------
darkmode      !byte 0
fgcol         !byte 1        ; encre par defaut
statuslinecol !byte 0
zcolours      !byte 0,1,2,3,4,5,6,7,0,1,2,3,4,5,6,7  ; table z-couleur -> Oric (a affiner)

; --- variables d'etat ecran (definies ici, comme dans screenkernal.asm) ------
s_screen_width            !byte 40
s_screen_width_minus_one  !byte 39
s_screen_width_plus_one   !byte 41
s_screen_height           !byte 28
s_screen_height_minus_one !byte 27
s_screen_size             !byte <1120, >1120
s_scrolled_lines          !byte 0
