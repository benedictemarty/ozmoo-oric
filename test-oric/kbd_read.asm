; Test : read_key renvoie l'ASCII d'une touche tapee -> affiche a l'ecran.
	* = $9000
	sei
	jsr kbd_init
poll
	jsr read_key
	beq poll               ; attend une touche
	sta $bb80              ; affiche l'ASCII lu
fin	jmp fin
	!source "../asm/keyboard-oric.asm"
