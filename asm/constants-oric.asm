; =============================================================================
; constants-oric.asm — cible ORIC-1 / Atmos (portage Ozmoo)
; -----------------------------------------------------------------------------
; Remplace constants.asm pour TARGET_ORIC. Fournit :
;   (1) la carte machine Oric (ecran, memoire, banking overlay Microdisc)
;   (2) le bloc zero-page independant-machine du moteur Z (copie de constants.asm)
;   (3) les points d'entree systeme (KERNAL Commodore -> equivalents Oric/Sedoric)
;
; STATUT : SQUELETTE (increment 0). Les symboles marques ">>> PORT TODO" doivent
; recevoir leur implementation Oric avant qu'un binaire fonctionnel soit produit.
; Banc de test : emulateur Phosphoric (~/Oric1, Microdisc WD1793 + Sedoric).
; Voir docs/PORTING_ORIC.md pour l'architecture et le backlog.
; =============================================================================

; --- MACHINE : ORIC-1 / Atmos ------------------------------------------------
; Ecran TEXT 40x28 en $BB80 (attributs "serie" inseres dans le flux, PAS de
; colour-map separee comme le VIC/TED). D'ou NO_COLOUR_MAP (nouveau drapeau de
; port) : tout le code supposant COLOUR_ADDRESS doit etre garde par ce drapeau.
NO_COLOUR_MAP         = 1

SCREEN_WIDTH          = 40
SCREEN_HEIGHT         = 28
SCREEN_ADDRESS        = $bb80        ; RAM ecran TEXT Oric
; COLOUR_ADDRESS      = <inexistant> ; >>> PORT : attributs serie, cf screenkernal-oric
CHARSET_STANDARD      = $b400        ; jeu de caracteres standard (RAM)
CHARSET_ALT           = $b800        ; jeu alternatif

; Banking overlay : avec Microdisc, $C000-$FFFF bascule ROM<->RAM overlay.
; read_track_sector ecrit $0314=$80 -> ROM BASIC off (b1=0) ET EPROM off (b7=1)
; (persiste sous SEI, Sedoric ne tourne plus). PROUVE (test-oric/bank_e000.sh) :
; $C000-$DFFF ET $E000-$FFFF sont TOUS DEUX de la RAM sous $0314=$80 -> 16 Ko d'overlay
; potentiels. Le banking actuel n'exploite QUE $C000-$DFFF (8 Ko) ; etendre a $E000-$FFFF
; (banking 16 Ko) exige de revectoriser/abandonner $FFFA-$FFFF (OK car deja SEI) et de
; reloger le vmap sous $E000 -- a faire APRES stabilisation du banking 8 Ko.
; --- OPT-IN via -DORIC_BANKING (EXPERIMENTAL, OFF par defaut) ---
; ON : banking 16 Ko. Les blocs VMEM etendus ($C000-$FDFF) sont adresses DIRECTEMENT
;   (pas de cache) ; first_banked_memory_page=$FF desactive le chemin cache (aucun bloc
;   n'atteint $FF) ; les blocs du trou charset/ecran $B4-$BF sont skippes vers $C0+
;   (cf. vmem.asm). $E000-$FFFF est de la RAM sous $0314=$80 (EPROM off, prouve v0.36.3) :
;   on l'ajoute a la zone de blocs (v0.36.8) ; vmap relogé $FE00-$FEFF (128 entrees) ;
;   $FF00-$FFFF laisse libre (vecteurs $FFFA-$FFFF non utilises car SEI). VMEM_END_PAGE=$FE.
;   Gain HHGG 42->59 blocs (~40% de faults en moins). Le CRASH V5 initial (advent) a ete
;   ROOT-CAUSE puis CORRIGE en v0.36.1 : c'etait s_scroll_oric qui debordait de l'ecran
;   (compteur de lignes sous-debordant quand une fenetre haute V5 = ecran entier) et
;   corrompait $C000-$DFFF (vmap + blocs). Banking desormais data-correct (vmap propre,
;   pas de crash). Reste OFF par defaut le temps de polir l'affichage sous scroll intensif
;   (bug num_rows/word-wrap pre-existant, plus visible en banking a cause du boot plus lent).
; OFF (defaut) : comportement stable v0.35.0 (VMEM_END_PAGE=$B0, vmap $B000, pas de skip).
!ifdef ORIC_BANKING {
first_banked_memory_page = $ff       ; $C000-$FDFF adressables directs (romdis+EPROM off)
} else {
first_banked_memory_page = $c0
}

; Reset (Atmos BASIC 1.1). >>> PORT : verifier point d'entree exact.
basic_reset           = $c000        ; >>> PORT TODO (cold start Atmos ~ $F88F)

; --- ZERO PAGE (moteur Z, independant-machine) -------------------------------
; NB : copie fidele de constants.asm. >>> PORT : valider l'absence de conflit
; avec l'usage zero-page de la ROM Oric / Sedoric (page $00 partiellement reservee).
zero_datadirection    = $00
zero_processorports   = $01
z_opcode              = $02
mem_temp              = $05 ; 2 bytes
z_extended_opcode     = $07
mempointer_y          = $08 ; 1 byte
z_opcode_number       = $09
zp_pc_h               = $0a
zp_pc_l               = $0b
z_operand_count       = $0d
zword                 = $0e ; 6 bytes
zp_mempos             = $14 ; 2 bytes
z_operand_value_high_arr = $16
z_operand_value_low_arr  = $1e

; Bloc contigu sauvegarde/restaure (doit rester contigu) :
z_local_vars_ptr      = $75 ; 2 bytes
z_local_var_count     = $77
stack_pushed_bytes    = $78 ; 2 bytes
stack_ptr             = $7a ; 2 bytes
stack_top_value       = $7c ; 2 bytes
stack_has_top_value   = $7e
z_pc                  = $7f ; 3 bytes
z_pc_mempointer       = $81 ; 2 bytes
zp_save_start         = z_local_vars_ptr
zp_bytes_to_save      = z_pc + 3 - z_local_vars_ptr

vmap_max_entries      = $34
zchar_triplet_cnt     = $35
packed_text           = $36 ; 2 bytes
alphabet_offset       = $38
escape_char           = $39
escape_char_counter   = $3a
abbreviation_command  = $40
parse_array           = $41 ; 2 bytes
string_array          = $43 ; 2 bytes
z_address             = $45 ; 3 bytes
z_address_temp        = $48
object_tree_ptr       = $49 ; 2 bytes
object_num            = $4b ; 2 bytes
object_temp           = $4d ; 2 bytes
vmap_used_entries     = $4f
z_low_global_vars_ptr = $50 ; 2 bytes
z_high_global_vars_ptr= $52 ; 2 bytes
z_trace_index         = $54
z_exe_mode            = $55
stack_tmp             = $56 ; 5 bytes
default_properties_ptr= $5b ; 2 bytes
zchars                = $5d ; 3 bytes
vmap_quick_index_match= $60
vmap_next_quick_index = $61
vmap_quick_index      = $62
vmap_quick_index_length = 6
z_temp                = $68 ; 12 bytes
s_colour              = $74
mempointer            = $26 ; 2 bytes
vmem_temp             = $92 ; 2 bytes
current_window        = $d8
s_stored_x            = $b4
s_stored_y            = $b5
s_current_screenpos_row = $b6
max_chars_on_line     = $bd
buffer_index          = $be
last_break_char_buffer_pos = $bf
zp_cursorswitch       = $cc
zp_screenline         = $d1 ; 2 bytes
zp_screencolumn       = $d3
zp_screenrow          = $d6
cursor_row            = $f7 ; 2 bytes
cursor_column         = $f9 ; 2 bytes
s_ignore_next_linebreak = $b0 ; 3 bytes
zp_temp               = $fb ; 5 bytes
savefile_zp_pointer   = $c1 ; 2 bytes

print_buffer          = $0100 ; SCREEN_WIDTH + 1 ; >>> PORT : chevauche pile 6502, a reloger
print_buffer2         = $0200
memory_buffer         = $02a7 ; >>> PORT : valider zone libre Oric
memory_buffer_length  = 89

; Buffers VMEM (pagination disque). >>> PORT : placer en zone RAM libre Oric.
directory_buffer      = $0400 ; >>> PORT TODO
; Sur C64 le vmap est en $0334 (buffer cassette libre). Historique du portage Oric :
;  - page $03 = PAGE SYSTÈME (I/O VIA/Microdisc + workspace ROM/Sedoric) → écrasait le vmap.
;  - page $02 (essai v0.28.0) : COLLISION avec print_buffer2 ($0200), keyboard_buff ($0277),
;    key_repeat, charset_switchable → print_line_from_buffer écrasait le vmap à CHAQUE
;    impression de texte → faults suivants mal mappés → z_pc lisait le mauvais bloc →
;    opcodes erronés (ex. insert_obj pendant Jumps) → 7 échecs czech en high memory.
; Relogé en RAM HAUTE LIBRE, sous le charset $B400. En mode banking (-DORIC_BANKING 16 Ko)
;  les blocs VMEM occupent $B000-$B3FF puis $C000-$FDFF -> le vmap est reloge tout en haut
;  de la RAM overlay ($FE00-$FEFF, 128 entrees, juste au-dessus des blocs) ; $FF00-$FFFF
;  reste libre (vecteurs non utilises car SEI).
;  Sans banking (defaut) : $B000-$B0CC (102 entrees), zone $A600-$B3FF libre.
!ifdef ORIC_BANKING {
vmap_buffer_start     = $FE00
vmap_buffer_end       = $FF00
} else {
vmap_buffer_start     = $B000
vmap_buffer_end       = $B0CC
}
CURRENT_DEVICE        = $00   ; >>> PORT : notion de "device" Sedoric

; --- Symboles complementaires (placeholders de portage) ----------------------
; Normalement definis par-cible dans constants.asm. Valeurs Oric provisoires ;
; permettent a l'assemblage d'aboutir. Comportement runtime a implementer.
COLOUR_ADDRESS_DIFF   = 0        ; pas de colour-map sur Oric
zp_colourline         = $f3      ; 2 bytes ; >>> PORT : pointeur colour-map (inutilise Oric)
window_start_row      = $2a      ; 4 bytes
s_reverse             = $b3      ; etat video inverse (attribut serie Oric)
keyboard_buff_len     = $c6      ; >>> PORT : longueur buffer clavier Oric
keyboard_buff         = $0277    ; >>> PORT : buffer clavier Oric
key_repeat            = $028a    ; >>> PORT : gestion repetition touche
charset_switchable    = $0291    ; >>> PORT : bascule jeu de caracteres
; kernal_delay_1ms : label reel defini dans keyboard-oric.asm (EPIC 3)

; Registres "raster" du VIC/TED : inexistants sur l'ULA Oric.
; Placeholders pour l'assemblage ; la synchro scroll passera par le VIA 6522.
reg_rasterline_highbit = $0000   ; >>> PORT TODO (synchro via timer VIA)
reg_rasterline         = $0000   ; >>> PORT TODO
rasterline_for_scroll  = 0       ; >>> PORT TODO

; Registres couleur VIC/TED : inexistants (Oric = attributs serie). Placeholders.
COLOUR_ADDRESS        = SCREEN_ADDRESS ; coherent avec COLOUR_ADDRESS_DIFF=0
reg_bordercolour      = $0000    ; >>> PORT TODO (bordure via attribut Oric)
reg_backgroundcolour  = $0000    ; >>> PORT TODO (papier via attribut Oric)

; Variables d'etat ecran (placeholders) :
num_rows              = $b7      ; >>> PORT : nb lignes fenetre courante
is_buffered_window    = $ab      ; >>> PORT : fenetre bufferisee ?

; --- Points d'entree KERNAL references par le moteur (placeholders) ----------
; TOUS a remplacer par des routines Oric/Sedoric (screenkernal-oric / disk-oric).
kernal_reset          = basic_reset ; >>> PORT TODO (cold reset Oric)
kernal_readst         = $0000       ; >>> PORT TODO (statut I/O)
kernal_setlfs         = $0000       ; >>> PORT TODO
kernal_setnam         = $0000       ; >>> PORT TODO
kernal_open           = $0000       ; >>> PORT TODO
kernal_close          = $0000       ; >>> PORT TODO
kernal_chkin          = $0000       ; >>> PORT TODO
kernal_chkout         = $0000       ; >>> PORT TODO
kernal_clrchn         = $0000       ; >>> PORT TODO
kernal_readchar       = $0000       ; >>> PORT TODO (lecture clavier Oric)
kernal_printchar      = $0000       ; >>> PORT TODO (affichage caractere Oric)
kernal_load           = $0000       ; >>> PORT TODO (chargement Sedoric)
kernal_save           = $0000       ; >>> PORT TODO (sauvegarde Sedoric)
kernal_settime        = $0000       ; >>> PORT TODO (VIA 6522)
kernal_readtime       = $0000       ; >>> PORT TODO (VIA 6522)
; kernal_getchar : label reel defini dans keyboard-oric.asm (EPIC 3, non bloquant)

; =============================================================================
; POINTS D'ENTREE SYSTEME — a reimplementer en Oric/Sedoric
; -----------------------------------------------------------------------------
; Ozmoo appelle ces routines type KERNAL Commodore. Sur Oric elles n'existent
; pas : chacune doit etre fournie par screenkernal-oric.asm / disk-oric.asm.
; Ce sont les JALONS du portage (voir backlog docs/PORTING_ORIC.md).
;   ecran/clavier : printchar, readchar, getchar
;   fichier/disque: setlfs, setnam, open, close, chkin, chkout, clrchn, load, save, readst
;   horloge       : settime, readtime (saisie temporisee V5 -> timer VIA 6522)
; >>> PORT TODO : definir kernal_* = <routine Oric> une fois screenkernal/disk ecrits.
; =============================================================================
