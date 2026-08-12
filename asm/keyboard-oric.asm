; =============================================================================
; keyboard-oric.asm — lecture clavier ORIC pour Ozmoo (cible ORIC)
; -----------------------------------------------------------------------------
; Scan de la matrice 8x8 : colonne via VIA ORB $0300 bits0-2 (74LS138),
; ligne via masque PSG R14 (~(1<<row)), detection sur VIA PB3.
; Sequence PSG (VIA PCR $030C) : latch=$EE, write=$EC, inactif=$CC.
; Prerequis : PSG R7 bit6=1 (port A en entree). Validé sur Phosphoric ('1'->col0 row5).
;
; read_key : renvoie l'ASCII de la 1ere touche pressee (0 si aucune), non bloquant.
; ay_write / registres préservés. Table (col*8+row)->ASCII : keyboard-oric-table.asm.
; =============================================================================

kbd_reg = $0301        ; VIA ORA (bus données PSG)
kbd_orb = $0300        ; VIA ORB (colonne / PB3)
kbd_pcr = $030c        ; VIA PCR (BDIR/BC1)

; --- kbd_init : DDRB (PB0-2 sortie, PB3 entrée) + PSG R7 bit6=1 --------------
kbd_init
	lda $0302
	ora #$07
	and #$f7
	sta $0302
	lda #7
	sta kay_reg
	lda #$ff
	sta kay_val
	jsr kay_write
	rts

; --- kernal_getchar : GETIN Oric (non bloquant) + anti-rebond ---------------
; Contrat KERNAL C64 ($FFE4) : A = ASCII de la touche, 0 si aucune. read_key
; fait un scan LIVE de la matrice (pas de buffer KERNAL) -> une touche maintenue
; serait renvoyee a chaque appel (des milliers/s dans la boucle de saisie).
; Anti-rebond : ne renvoie une touche que si elle DIFFERE de la precedente
; (nouvelle frappe ou relachement intermediaire) ; une touche tenue -> 0.
; Registres clobbes (comme GETIN) : A,X,Y.
kernal_getchar
	jsr read_key
	cmp kbd_last_key
	beq .held             ; identique a la precedente -> supprimee (tenue / 0)
	sta kbd_last_key      ; nouvelle touche (ou relachement) -> memorise + renvoie
	rts
.held
	lda #0
	rts

kbd_last_key !byte 0

; --- kernal_delay_1ms : temporisation ~1 ms (Oric ~1 MHz) --------------------
; PRESERVE A,X,Y : wait_yx_ms (disk.asm) boucle avec X/Y comme compteurs autour
; de cet appel -> il ne doit PAS les alterer. Boucle calibree : 200 iterations
; de dex/bne (5 cy) ~= 1000 cy ~= 1 ms.
kernal_delay_1ms
	pha
	txa
	pha
	tya
	pha
	ldx #200
-	dex
	bne -
	pla
	tay
	pla
	tax
	pla
	rts

; --- read_key : ASCII en A (0 si aucune touche) -----------------------------
read_key
	ldx #0                 ; colonne
rk_col
	lda kbd_orb
	and #$f8
	sta ktmp
	txa
	ora ktmp
	sta kbd_orb            ; sélection colonne
	ldy #0                 ; ligne
rk_row
	lda krc_rowmask,y
	sta kay_val
	lda #14
	sta kay_reg
	jsr kay_write          ; R14 = ~(1<<row) ; préserve X,Y
	lda kbd_orb
	and #$08               ; PB3 ?
	bne rk_found
	iny
	cpy #8
	bne rk_row
	inx
	cpx #8
	bne rk_col
	lda #0                 ; aucune touche
	rts
rk_found
	; index = col*8 + row (X=col, Y=row)
	txa
	asl
	asl
	asl
	sty ktmp
	ora ktmp
	tax
	lda krc_to_ascii,x
	rts

; --- kay_write : écrit kay_val dans registre kay_reg (préserve A,X,Y) --------
kay_write
	pha
	txa
	pha
	tya
	pha
	lda kay_reg
	sta kbd_reg
	lda #$ee
	sta kbd_pcr
	lda #$cc
	sta kbd_pcr
	lda kay_val
	sta kbd_reg
	lda #$ec
	sta kbd_pcr
	lda #$cc
	sta kbd_pcr
	pla
	tay
	pla
	tax
	pla
	rts

krc_rowmask !byte $fe,$fd,$fb,$f7,$ef,$df,$bf,$7f
kay_reg !byte 0
kay_val !byte 0
ktmp    !byte 0

; table (col*8+row)->ASCII non-shiftee (extrait de keyboard.c ; incomplète — TODO
; compléter lettres/shift). Suffit à valider le chemin scan->ASCII.
krc_to_ascii
	!byte $37,$00,$35,$00,$00,$31,$00,$33
	!byte $00,$00,$00,$00,$00,$00,$00,$00
	!byte $00,$36,$00,$34,$00,$00,$32,$00
	!byte $00,$39,$3b,$2d,$00,$00,$5c,$27
	!byte $20,$2c,$2e,$00,$00,$00,$00,$00
	!byte $00,$00,$00,$00,$00,$00,$5d,$5b
	!byte $00,$00,$00,$00,$00,$61,$00,$00
	!byte $38,$00,$30,$2f,$00,$00,$00,$3d
