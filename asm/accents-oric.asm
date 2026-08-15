; =============================================================================
; accents-oric.asm — rendu des caractères accentués FRANÇAIS sur l'écran Oric
; -----------------------------------------------------------------------------
; L'Oric n'a pas d'accents dans sa police. On les AJOUTE au boot : pour chaque
; accent, on part du glyphe de la lettre de base (charset RAM $B400) et on
; surimpose une marque d'accent, puis on écrit le résultat dans un slot de code
; écran « rare » réaffecté (symboles ASCII peu utilisés en prose française).
; translate_zscii_to_petscii (streams.asm, garde ORIC_ACCENTS) mappe les codes
; ZSCII accentués (155-251) vers ces codes écran.
;
; Deux modes (les MINUSCULES ont les rangées 0-1 libres, pas les MAJUSCULES) :
;   - minuscule : copie directe + marque 2 rangées (0-1).
;   - MAJUSCULE : lettre décalée d'1 rangée vers le bas (1-7) + marque 1 rangée (0).
;   - cédille (ç/Ç) : pas de décalage, cédille en rangée 7.
; Encodage oric_accent_mark : bits 0-2 = index marque (0=aigu 1=grave 2=circ
;   3=tréma 4=aucune) ; bit6 = MAJUSCULE (décalage+marque 1 rangée) ; bit7 = cédille.
;
; Charset Oric : glyphe du code C à $B400 + C*8 ; 8 rangées, 6 px (bit 5 = gauche).
; Utilise les pointeurs ZP $fb/$fc (source) et $fd/$fe (dest) — libres au boot.
; =============================================================================

N_ACCENTS = 19

oric_accent_zscii
	!byte 170,182,192,164,181,191,185,195,193,165,194,213,157,156   ; é è ê ë à â ù û î ï ô ç ü ö
	!byte 176,187,186,214,197                                       ; É È À Ç Ê
oric_accent_code
	!byte '{','}','~',96, 92,'^','[',']','_','@','#','$','%','&'     ; minuscules
	!byte '*','+','|','=','<'                                       ; majuscules
oric_accent_base
	!byte 'e','e','e','e','a','a','u','u','i','i','o','c','u','o'
	!byte 'E','E','A','C','E'
oric_accent_mark
	!byte 0,  1,  2,  3,  1,  2,  1,  2,  2,  3,  2,  $84,3,  3      ; ç = aucune+cédille
	!byte $40,$41,$41,$84,$42                                       ; É=maj+aigu È/À=maj+grave Ç=cédille Ê=maj+circ

; marques 2 rangées (minuscules), 2 octets/entrée, index 0-4
oric_mark2
	!byte %00000110,%00001100    ; 0 aigu
	!byte %00011000,%00001100    ; 1 grave
	!byte %00001100,%00010010    ; 2 circonflexe
	!byte %00010010,%00000000    ; 3 tréma
	!byte %00000000,%00000000    ; 4 aucune
; marques 1 rangée (majuscules), 1 octet/entrée, index 0-3
oric_mark1
	!byte %00001100    ; 0 aigu
	!byte %00011000    ; 1 grave
	!byte %00001010    ; 2 circonflexe
	!byte %00010010    ; 3 tréma
CEDIL_ROW = %00001100

.acc_x   !byte 0
.acc_m0  !byte 0
.acc_m1  !byte 0

; A = code écran -> pose $B400 + code*8 dans (lo)=A_out ; écrit dans $fb/$fc.
.set_src
	sta .acc_m0 : lda #0 : sta $fc : lda .acc_m0
	asl : rol $fc : asl : rol $fc : asl : rol $fc     ; *8
	sta $fb : lda $fc : clc : adc #$b4 : sta $fc
	rts
.set_dst
	sta .acc_m0 : lda #0 : sta $fe : lda .acc_m0
	asl : rol $fe : asl : rol $fe : asl : rol $fe
	sta $fd : lda $fe : clc : adc #$b4 : sta $fe
	rts

oric_load_accent_glyphs
	ldx #0
.al_next
	stx .acc_x
	lda oric_accent_base,x : jsr .set_src
	ldx .acc_x
	lda oric_accent_code,x : jsr .set_dst
	ldx .acc_x
	lda oric_accent_mark,x
	and #$40
	bne .al_upper
	; --- MINUSCULE : copie directe + marque 2 rangées ---
	ldy #7
.al_cl	lda ($fb),y : sta ($fd),y : dey : bpl .al_cl
	lda oric_accent_mark,x : and #$07 : asl : tay
	lda oric_mark2,y   : sta .acc_m0
	lda oric_mark2+1,y : sta .acc_m1
	ldy #0 : lda .acc_m0 : sta ($fd),y
	iny    : lda .acc_m1 : sta ($fd),y
	jmp .al_ced
.al_upper
	; --- MAJUSCULE : copie décalée (dst[r+1]=src[r], r=0..6) + marque 1 rangée ---
	ldy #6
.al_cu	lda ($fb),y : iny : sta ($fd),y : dey : dey : bpl .al_cu
	lda oric_accent_mark,x : and #$07 : tay
	lda oric_mark1,y
	ldy #0 : sta ($fd),y
.al_ced
	lda oric_accent_mark,x
	bpl .al_noced
	ldy #7 : lda #CEDIL_ROW : sta ($fd),y
.al_noced
	inx
	cpx #N_ACCENTS
	bne .al_next
	rts
