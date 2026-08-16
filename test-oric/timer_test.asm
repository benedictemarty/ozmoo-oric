; Valide l'horloge jiffy VIA Timer 1 (saisie temporisée). Configure T1 en free-run
; 60 Hz (latch 16667 @ 1 MHz), polle le flag de débordement (IFR bit6) dans une double
; boucle (~65536 itérations ≈ 0,65 s de temps émulé), compte les jiffys, et affiche le
; compte (2 chiffres hexa) en $BB80. Attendu ≈ $27 (39 jiffys pour 0,65 s).
	* = $9000
	sei
	; T1 continu 60 Hz
	lda $030b : and #$7f : ora #$40 : sta $030b
	lda #$1b : sta $0306        ; T1L-L (16667 = $411B)
	lda #$41 : sta $0305        ; T1C-H : démarre
	lda #0 : sta $50            ; compteur jiffys (bas)
	; poll : Y(0..255) x X(0..255) iterations, chacune teste IFR bit6
	ldy #0
.outer	ldx #0
.inner	lda $030d : and #$40 : beq +
	lda $0304 : inc $50         ; lit T1C-L (efface flag) + compte
+	dex : bne .inner
	iny : bne .outer
	; affiche $50 en hexa (2 chiffres) en $BB80/$BB81
	lda $50 : lsr : lsr : lsr : lsr : jsr .hex : sta $bb80
	lda $50 : and #$0f : jsr .hex : sta $bb81
.end	jmp .end
.hex	cmp #10 : bcc + : adc #6   ; +7 (carry set) -> A-F
+	adc #$30 : rts
