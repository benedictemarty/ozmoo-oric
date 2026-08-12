; =============================================================================
; disk-oric.asm — acces disque Microdisc/WD1793 pour Ozmoo (cible ORIC)
; -----------------------------------------------------------------------------
; Fournit read_track_sector, la SEULE routine disque machine-specifique du moteur
; (readblock/readblocks/VMEM au-dessus sont portables). Validee sur Phosphoric :
; lecture piste0/secteur1 ET seek+lecture piste2/secteur3 (contenu connu verifie).
;
; Registres Microdisc (source d'autorite = emulateur) :
;   $0310 commande(w)/statut(r)  ($01=BUSY, $02=DRQ)
;   $0311 piste   $0312 secteur   $0313 data
;   $0314 controle : drive(b5-6) side(b4) ROMDIS(b1) EPROM(b7) INTENA(b0)
; Commandes WD1793 : $00 Restore, $10 Seek (cible = registre data), $80 Read Sector.
;
; NB : ce fichier est la version STANDALONE (testée via test-oric/*). La version
; INTÉGRÉE au moteur est inline dans disk.asm sous `!ifdef TARGET_ORIC` (au point
; `.have_set_device_track_sector`), car readblock y saute avec .track/.sector déjà
; remplis et utilise `zp_mempos` (pointeur ZP) — `readblocks_mempos` d'Ozmoo étant
; en mémoire absolue. Garder les deux logiques en phase.
; =============================================================================

FDC_CMD    = $0310
FDC_STATUS = $0310
FDC_TRACK  = $0311
FDC_SECTOR = $0312
FDC_DATA   = $0313
FDC_CTRL   = $0314

; --- read_track_sector -------------------------------------------------------
; Contrat Ozmoo : A = piste, X = secteur, Y = device (ignore : mono-lecteur),
; mot en readblocks_mempos = adresse de destination. Lit 256 octets.
read_track_sector
	sta rts_track
	stx rts_sector
	lda #$80              ; drive 0, side 0, EPROM overlay off, IRQ off
	sta FDC_CTRL
	lda #$00              ; Restore -> piste 0 (cale c_track)
	sta FDC_CMD
	jsr rts_wait_ready
	lda rts_track         ; Seek vers la piste cible
	sta FDC_DATA          ; data = piste cible
	lda #$10
	sta FDC_CMD           ; Seek
	jsr rts_wait_ready
	lda rts_sector
	sta FDC_SECTOR
	lda #$80
	sta FDC_CMD           ; Read Sector
	ldy #0
rts_loop
	lda FDC_STATUS
	and #$01              ; BUSY ?
	beq rts_done          ; commande terminee
	lda FDC_STATUS
	and #$02              ; DRQ ?
	beq rts_loop          ; pas encore de donnee
	lda FDC_DATA
	sta (readblocks_mempos),y
	iny
	bne rts_loop
rts_done
	rts

; attend la fin d'une commande Type I (BUSY relache), avec tempo initiale
rts_wait_ready
	ldx #$40
-	dex
	bne -
rwr	lda FDC_STATUS
	and #$01
	bne rwr
	rts

rts_track  !byte 0
rts_sector !byte 0
