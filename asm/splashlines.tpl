splashline0
!ifdef TARGET_ORIC {
	!pet "        * * * * * * * * * * * * * *", 0
} else {
	!pet "@0s@", 0
}
splashline1
!ifdef TARGET_ORIC {
	!pet "             Benedicte Marty", 0
} else {
	!pet "@1s@", 0
}
splashline2
!ifdef TARGET_ORIC {
	!pet "               Ozmoo Oric-0.1", 0
} else {
	!pet "@2s@", 0
}
splashline3
!ifdef TARGET_ORIC {
	!pet "                 @date@", 0
} else {
	!pet "@3s@", 0
}
splashline4
!ifdef UNDO {
	!pet "          Ozmoo @vs@ with Undo",0
} else {
	!pet "               Ozmoo @vs@",0
}

splashline5
!ifndef NODARKMODE {
	!ifdef SCROLLBACK {
		!pet "        F1=Darkmode F5=Scrollback",0
	} else {
		!pet "               F1=Darkmode",0
	}
} else {
	!ifdef SCROLLBACK {
		!pet "              F5=Scrollback",0
	} else {
		!pet " ",0
	}
}
!ifdef UNDO {
!ifndef Z5PLUS {
SHOWUNDO=1
}
}

splashline6
!ifdef TARGET_X16 {
	!pet "       Ctrl: 0-8=Scroll slowness",0
} else ifdef SHOWUNDO {
	!pet " Ctrl: D=Reset device# K=Key rpt U=Undo",0
} else {
	!pet "   Ctrl: D=Reset device# K=Key repeat",0
}

splashline7
!ifdef SMOOTHSCROLL {
	!pet "  0-8=Scroll slowness, 9=Smooth scroll",0
!ifdef TARGET_C128 {
splashline7alt
	!pet "           0-8=Scroll slowness",0
}
} else ifdef TARGET_X16 {
	!pet "",0
} else {
	!pet "           0-8=Scroll slowness",0
}


splash_index_col
	!byte @0c@, @1c@, @2c@, @3c@, 0, 0, 0, 0

