; Test EPIC 4 : lire piste0/secteur1 via WD1793 Microdisc, directement a l'ecran.
; Registres : $0310 cmd/statut, $0311 piste, $0312 secteur, $0313 data, $0314 ctrl.
	* = $9000
	sei
	; selectionne drive 0, side 0 (EPROM overlay off, pas d'IRQ)
	lda #$80
	sta $0314
	; Restore : seek piste 0 (c_track=0)
	lda #$00
	sta $0310
	jsr fdc_wait_ready
	; secteur = 1, piste = 0
	lda #0
	sta $0311
	lda #1
	sta $0312
	; commande Read Sector ($80)
	lda #$80
	sta $0310
	; boucle de lecture : 256 octets -> ecran $BB80
	ldy #0
rdloop
	lda $0310         ; statut
	and #$01          ; BUSY ?
	beq rddone        ; plus busy -> fini
	lda $0310
	and #$02          ; DRQ ?
	beq rdloop        ; pas encore de donnee
	lda $0313         ; lit l'octet
	sta $bb80,y       ; -> ecran
	iny
	bne rdloop
rddone
	jmp rddone

; attend la fin d'une commande Type I (BUSY relache)
fdc_wait_ready
	ldx #$40          ; petite tempo avant de tester BUSY
-	dex
	bne -
fwr	lda $0310
	and #$01
	bne fwr
	rts
