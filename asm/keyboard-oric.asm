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

; table (col*8+row)->ASCII (matrice non-shiftée complète, INVERSE de char_map dans
; ~/Oric1/src/io/keyboard.c). Lettres en MINUSCULES (les jeux Z-machine saisissent en
; minuscule ; l'écran Oric est en ASCII standard). Touches spéciales requises par la
; saisie ligne read_text : RETURN (col7,row5)=$0d (13), DELETE (col5,row5)=$08 (8).
; Les $00 = positions modificateurs (SHIFT col4/7 row4, CTRL col2 row4, FUNCT col5 row4),
; flèches (col4 row3/5/6/7), ESC (col1 row5) : ignorées par la saisie ligne.
krc_to_ascii
	; col0 : 7 n 5 v . 1 x 3
	!byte $37,$6e,$35,$76,$00,$31,$78,$33
	; col1 : j t r f . (ESC) q d
	!byte $6a,$74,$72,$66,$00,$00,$71,$64
	; col2 : m 6 b 4 . z 2 c
	!byte $6d,$36,$62,$34,$00,$7a,$32,$63
	; col3 : k 9 ; - . . \ '
	!byte $6b,$39,$3b,$2d,$00,$00,$5c,$27
	; col4 : espace , . (UP)(LSHIFT)(LEFT)(DOWN)(RIGHT)
	!byte $20,$2c,$2e,$00,$00,$00,$00,$00
	; col5 : u i o p (FUNCT) DEL=8 ] [
	!byte $75,$69,$6f,$70,$00,$08,$5d,$5b
	; col6 : y h g e . a s w
	!byte $79,$68,$67,$65,$00,$61,$73,$77
	; col7 : 8 l 0 / (RSHIFT) RETURN=13 . =
	!byte $38,$6c,$30,$2f,$00,$0d,$00,$3d

; =============================================================================
; Horloge jiffy (1/60 s) pour la SAISIE TEMPORISÉE (@read/@read_char avec délai).
; Sous SEI l'IRQ ROM ne tourne pas -> on lit le temps en pollant le VIA Timer 1
; (6522) configuré en free-run 60 Hz (latch 16667 @ 1 MHz). kernal_readtime/settime
; y pointent (constants-oric.asm). oric_time_init appelé à program_start.
; VIA : ACR=$030B, T1C-L=$0304, T1C-H=$0305, T1L-L=$0306, IFR=$030D.
; NB : compte 1 débordement par appel -> exact tant que readtime est pollé >= 60 Hz
; (cas de la boucle de lecture Ozmoo). Approx sinon.
oric_jiffies !byte 0, 0, 0

oric_time_init
	lda $030b
	and #$7f          ; PB7 désactivé (bit7=0)
	ora #$40          ; T1 continu / free-run (bit6=1)
	sta $030b
	lda #$1b : sta $0306   ; T1L-L (16667 = $411B)
	lda #$41 : sta $0305   ; T1C-H : démarre le timer, charge le latch, efface IFR b6
	lda #0
	sta oric_jiffies
	sta oric_jiffies + 1
	sta oric_jiffies + 2
	rts

; kernal_readtime : renvoie le temps courant en jiffys, A=bas X=milieu Y=haut.
oric_readtime
	lda $030d         ; IFR
	and #$40          ; débordement T1 ?
	beq .ort_ret
	lda $0304         ; lire T1C-L efface le flag IRQ T1
	inc oric_jiffies
	bne .ort_ret
	inc oric_jiffies + 1
	bne .ort_ret
	inc oric_jiffies + 2
.ort_ret
	lda oric_jiffies
	ldx oric_jiffies + 1
	ldy oric_jiffies + 2
	rts

; kernal_settime : fixe l'horloge à A=bas X=milieu Y=haut.
oric_settime
	sta oric_jiffies
	stx oric_jiffies + 1
	sty oric_jiffies + 2
	rts

; --- Bip AY-3-8912 (@sound_effect) : joue une tonalité brève sur le canal A. --------
; X = période de tonalité (R0 fine ; grand = grave). Utilise kay_write (PSG via VIA).
; Préserve R7 bit6=1 (IOA output, requis par le scan clavier). ~150 ms puis silence.
oric_beep
	lda #0 : sta kay_reg : stx kay_val : jsr kay_write   ; R0 = période (fine)
	lda #1 : sta kay_reg : lda #0 : sta kay_val : jsr kay_write   ; R1 = 0 (coarse)
	lda #7 : sta kay_reg : lda #$7e : sta kay_val : jsr kay_write ; R7 : tonalité A ON, IOA out
	lda #8 : sta kay_reg : lda #$0f : sta kay_val : jsr kay_write ; R8 : volume A = 15
	ldx #150
-	jsr kernal_delay_1ms
	dex : bne -
	lda #8 : sta kay_reg : lda #0 : sta kay_val : jsr kay_write   ; R8 = 0 (silence)
	lda #7 : sta kay_reg : lda #$7f : sta kay_val : jsr kay_write ; R7 : tonalités OFF, IOA out
	rts
