; Repro ISOLE de l'interaction unbuffered + scroll sur la DERNIERE ligne.
; Reproduit le chemin de la saisie non-bufferisee (is_buffered_window=0) : le jeu
; (ex. tip PunyInform "Did you know...") imprime caractere par caractere via s_printchar,
; qui hard-wrap a la colonne 40 et, sur la derniere ligne, appelle s_scroll_oric.
; On mime l'etat fenetre capture au garble : window_start_row=[height,0] (plein ecran).
	* = $9000
	sei
	jsr s_init
	; etat fenetre : plein ecran, aucune ligne protegee (comme au tip banking)
	lda s_screen_height
	sta window_start_row          ; [0] = 28
	lda #0
	sta window_start_row + 1      ; [1] = 0 (protect = 0)
	sta window_start_row + 2
	sta window_start_row + 3
	; descendre sur la DERNIERE ligne : height-1 retours-chariot
	ldx s_screen_height
	dex
nl	lda #13
	jsr s_printchar
	dex
	bne nl
	; imprimer une longue chaine SANS CR (110 chars) -> wrappe ~3x sur la derniere
	; ligne, chaque wrap declenche s_scroll_oric. Chaque bloc de 40 doit apparaitre
	; PROPREMENT sur des lignes successives (scrollees), sans chevauchement.
	ldx #0
loop	lda msg,x
	beq done
	jsr s_printchar
	inx
	cpx #110
	bne loop
done	jmp done

; 110 chars distinctifs : chaque groupe de 10 marque sa position (0-9 A-J ...)
msg	!text "0123456789ABCDEFGHIJabcdefghij0123456789KLMNOPQRSTklmnopqrst0123456789UVWXYZ0189uvwxyz01890123456789PQRSTUVWXY",0

; --- equates ZP (fournies normalement par constants-oric.asm) ---------------
zp_screenline           = $d1
zp_screencolumn         = $d3
zp_screenrow            = $d6
s_colour                = $74
s_stored_x              = $b4
s_stored_y              = $b5
s_current_screenpos_row = $b6
window_start_row        = $2a
s_ignore_next_linebreak = $b0
s_reverse               = $b3

	!source "../asm/screenkernal-oric.asm"
