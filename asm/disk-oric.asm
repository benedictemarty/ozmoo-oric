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

; Pistes/face (seuil face 1). Défini par constants-oric.asm dans le build moteur ;
; fallback ici pour l'usage standalone (test-oric/*). Cf. read_track_sector.
!ifndef TRACKS_PER_SIDE {
TRACKS_PER_SIDE = 80
}

; --- read_track_sector -------------------------------------------------------
; Contrat Ozmoo : A = piste, X = secteur, Y = device (ignore : mono-lecteur),
; mot en readblocks_mempos = adresse de destination. Lit 256 octets.
read_track_sector
	sta rts_track
	stx rts_sector
	jsr rts_seek          ; setup commun : face + restore + seek + secteur
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

; --- write_track_sector ------------------------------------------------------
; Même contrat que read_track_sector (A=piste, X=secteur, source=readblocks_mempos).
; Écrit 256 octets sur le secteur (commande WD1793 $A0 Write Sector). Pour save/restore.
write_track_sector
	sta rts_track
	stx rts_sector
	jsr rts_seek
	lda #$a0
	sta FDC_CMD           ; Write Sector
	ldy #0
wts_loop
	lda FDC_STATUS
	and #$01              ; BUSY ?
	beq wts_done
	lda FDC_STATUS
	and #$02              ; DRQ ?
	beq wts_loop
	lda (readblocks_mempos),y
	sta FDC_DATA
	iny
	bne wts_loop
wts_done
	rts

; setup commun read/write : face (piste >= TRACKS_PER_SIDE -> face 1), restore, seek,
; secteur physique (readblock 0-based -> ID Sedoric/MFM 1-based, +1).
rts_seek
	ldx #$80              ; FDC_CTRL base : drive 0, side 0, EPROM off, IRQ off
	lda rts_track
	cmp #TRACKS_PER_SIDE
	bcc +
	sbc #TRACKS_PER_SIDE  ; (carry set par cmp) piste physique face 1
	sta rts_track
	ldx #$90              ; face 1 : side (b4) = 1
+	stx FDC_CTRL
	lda #$00              ; Restore -> piste 0
	sta FDC_CMD
	jsr rts_wait_ready
	lda rts_track         ; Seek vers la piste cible
	sta FDC_DATA
	lda #$10
	sta FDC_CMD           ; Seek
	jsr rts_wait_ready
	lda rts_sector
	clc
	adc #1
	sta FDC_SECTOR
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
