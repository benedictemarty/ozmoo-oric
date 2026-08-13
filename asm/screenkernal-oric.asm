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
	cmp #$08                  ; backspace/delete (8) -> efface le char precedent
	beq spc_backspace
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

; backspace/delete ($08) : recule d'une colonne et efface (retour visuel de la
; saisie ligne @sread ; read_text a deja decremente .read_text_column et attend
; que le char delete recule le curseur ecran + efface le caractere).
spc_backspace
	lda zp_screencolumn
	beq spc_done              ; deja en colonne 0 -> rien
	dec zp_screencolumn
	ldy zp_screencolumn
	lda #$20                  ; espace : efface le caractere supprime
	sta (zp_screenline),y
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

; --- s_scroll_oric : scrolle la fenetre basse d'UNE ligne en PROTEGEANT les
;     window_start_row+1 lignes du haut (status-line V3 = row 0). Deplace les lignes
;     [protect+1 .. height-1] vers [protect .. height-2] puis efface la derniere.
;     Avant : scrollait TOUT l'ecran (row 0 comprise) -> la status-line etait scrollee
;     et le modele de fenetres desynchronise -> lignes dupliquees au scroll. Code
;     auto-modifiant (les adresses src/dst sont patchees) pour ne pas toucher la ZP.
s_scroll_oric
	; dst = SCR_BASE + protect*40
	lda #<SCR_BASE
	sta sso_st + 1
	lda #>SCR_BASE
	sta sso_st + 2
	ldx window_start_row + 1        ; nb lignes protegees (0 = scroll plein ecran)
	beq sso_ptr_ok
sso_addprot
	clc
	lda sso_st + 1
	adc #40
	sta sso_st + 1
	bcc sso_np
	inc sso_st + 2
sso_np
	dex
	bne sso_addprot
sso_ptr_ok
	; src = dst + 40 (ligne du dessous)
	clc
	lda sso_st + 1
	adc #40
	sta sso_ld + 1
	lda sso_st + 2
	adc #0
	sta sso_ld + 2
	; nb lignes a deplacer = height - protect - 1
	lda s_screen_height
	sec
	sbc window_start_row + 1
	sbc #1
	tax
sso_line
	ldy #39
sso_byte
sso_ld	lda $ffff,y                     ; source (adresse patchee)
sso_st	sta $ffff,y                     ; destination (adresse patchee)
	dey
	bpl sso_byte
	clc                             ; dst += 40
	lda sso_st + 1
	adc #40
	sta sso_st + 1
	bcc sso_d2
	inc sso_st + 2
sso_d2
	clc                             ; src += 40
	lda sso_ld + 1
	adc #40
	sta sso_ld + 1
	bcc sso_s2
	inc sso_ld + 2
sso_s2
	dex
	bne sso_line
	; effacer la derniere ligne (sso_st pointe dessus)
	lda sso_st + 1
	sta sso_cl + 1
	lda sso_st + 2
	sta sso_cl + 2
	lda #$20
	ldy #39
sso_clr
sso_cl	sta $ffff,y
	dey
	bpl sso_clr
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

; --- s_erase_line_from_cursor (V5) : efface du curseur a la fin de la ligne ---
; Requis par z_ins_erase_line (erase_line 1) sous Z4PLUS. Efface les colonnes
; [zp_screencolumn .. s_screen_width-1] de la ligne courante (espaces).
s_erase_line_from_cursor
	txa
	pha
	tya
	pha
	jsr s_setline
	lda #$20
	ldy zp_screencolumn
selc_l	cpy s_screen_width
	bcs selc_done             ; curseur deja en fin de ligne -> rien a faire
	sta (zp_screenline),y
	iny
	bne selc_l               ; toujours (y < 40)
selc_done
	pla
	tay
	pla
	tax
	rts

; --- z_ins_set_colour (V5) : STUB Oric ---------------------------------------
; L'Oric est en attributs serie (NO_COLOUR_MAP) : pas de couleur premier plan/fond
; par cellule bon marche. set_colour ne stocke aucun resultat ; les operandes sont
; deja consommees par le decodeur. On ignore la couleur (a etoffer ulterieurement
; via insertion d'attributs serie). No-op fonctionnel.
z_ins_set_colour
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
