; =============================================================================
; accents-oric.asm — rendu des caractères accentués FRANÇAIS sur l'écran Oric
; -----------------------------------------------------------------------------
; L'Oric n'a pas d'accents dans sa police. On les AJOUTE au boot : pour chaque
; accent, on lit le glyphe de la lettre de base dans le charset RAM ($B400), on
; surimpose une marque d'accent (rangées 0-1, libres sur les minuscules) et une
; cédille (rangée 7), puis on écrit le glyphe résultant dans un slot de code écran
; « rare » réaffecté (symboles ASCII @ # $ % & [ \ ] ^ _ ` { } ~ peu utilisés en
; prose française). translate_zscii_to_petscii (streams.asm, garde TARGET_ORIC)
; mappe les codes ZSCII accentués (155-251) vers ces codes écran.
;
; Charset Oric : glyphe du code C à $B400 + C*8 ; 8 rangées, 6 px (bits 5..0,
; bit 5 = pixel de gauche).
; =============================================================================

N_ACCENTS = 14

; Codes ZSCII source (cf. table Unicode par défaut Z-machine, 155..)
oric_accent_zscii
	!byte 170,182,192,164,181,191,185,195,193,165,194,213,157,156
	;      é   è   ê   ë   à   â   ù   û   î   ï   ô   ç   ü   ö
; Code écran Oric cible (parallèle) — symboles réaffectés
oric_accent_code
	!byte '{','}','~',96, 92,'^','[',']','_','@','#','$','%','&'
; Lettre de base (code ASCII) dont on part
oric_accent_base
	!byte 'e','e','e','e','a','a','u','u','i','i','o','c','u','o'
; Index de marque (0=aigu 1=grave 2=circonflexe 3=tréma 4=aucune) ; bit7 = cédille
oric_accent_mark
	!byte 0,  1,  2,  3,  1,  2,  1,  2,  2,  3,  2,  $84,3,  3
	;     é   è   ê   ë   à   â   ù   û   î   ï   ô   ç   ü   ö

; Marques (rangées 0-1), 2 octets chacune, 6 px alignés à gauche
oric_mark_rows
	!byte %00000110,%00001100    ; 0 aigu   ´
	!byte %00011000,%00001100    ; 1 grave  `
	!byte %00001100,%00010010    ; 2 circonflexe ^
	!byte %00010010,%00000000    ; 3 tréma  ¨
	!byte %00000000,%00000000    ; 4 aucune (ç : marque nulle + cédille)
CEDIL_ROW = %00001100            ; cédille (rangée 7)

.mtmp !byte 0,0
.cta_lo !byte 0
.cta_savex !byte 0

; A = code écran -> renvoie l'adresse $B400 + code*8 (A=lo, Y=hi). Préserve X.
.code_to_addr
	stx .cta_savex
	asl : sta .cta_lo : lda #0 : rol   ; *2
	asl .cta_lo : rol                  ; *4
	asl .cta_lo : rol                  ; *8
	clc : adc #$b4 : tay               ; + $B400 -> hi
	lda .cta_lo
	ldx .cta_savex
	rts

; Construit tous les glyphes accentués dans le charset. À appeler au boot APRÈS que
; la police ROM est en place à $B400 (cas au démarrage Oric).
oric_load_accent_glyphs
	ldx #0
.al_next
	lda oric_accent_base,x
	jsr .code_to_addr
	sta .al_rd+1 : sty .al_rd+2          ; src = base
	lda oric_accent_code,x
	jsr .code_to_addr
	sta .al_wr+1 : sty .al_wr+2          ; dst (copie)
	sta .al_m0+1 : sty .al_m0+2          ; dst (marque r0)
	sta .al_m1+1 : sty .al_m1+2          ; dst (marque r1)
	sta .al_ced+1 : sty .al_ced+2        ; dst (cédille r7)
	; copie 8 octets base -> dst
	ldy #7
.al_rd	lda $b400,y
.al_wr	sta $b400,y
	dey
	bpl .al_rd
	; surimpose la marque (rangées 0-1)
	lda oric_accent_mark,x
	and #$0f
	asl                                  ; *2 (2 octets/marque)
	tay
	lda oric_mark_rows,y   : sta .mtmp
	lda oric_mark_rows+1,y : sta .mtmp+1
	ldy #0 : lda .mtmp
.al_m0	sta $b400,y
	ldy #1 : lda .mtmp+1
.al_m1	sta $b400,y
	; cédille (rangée 7) si bit7 du mark
	lda oric_accent_mark,x
	bpl .al_noced
	ldy #7 : lda #CEDIL_ROW
.al_ced	sta $b400,y
.al_noced
	inx
	cpx #N_ACCENTS
	bne .al_next
	rts
