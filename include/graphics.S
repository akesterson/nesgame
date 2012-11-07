  .require "defines.S"
	
	;; Function : paletteLoad
	;;
	;; Given the address of a palette in ROM or RAM, and the
	;; index of which palette to load (0=3F00, 1=3F10), load a
	;; palette into the PPU
	;;
	;; arguments are on the stack (in push order):
	;;     - 00 or 10, lyte byte of PPU palette address to load
	;;     - Low byte of palette address
	;;     - High byte of palette address
paletteLoad:
	.invoke storeStackReturn
	PLA
	STA curPaletteHi
	PLA
	STA curPaletteLo
	LDA $2002		; The PPU Memory address at $2006 expects
				; the high byte of the palette address first,
				; then the low byte, but we can't know
				; which one it's expecting right now, so we
				; read the PPU status at $2002 to reset the
				; high/low latch on $2006.
	LDA #$3F		; palettes live at $3F00 and $3F10
	STA $2006
	PLA
	STA $2006
	LDX #$00
_loop:	
	LDA (curPaletteLo), y	; Loop over each index of the byte array at
	STA $2007		; 'palette', store each one into the accumulator
	INY			; and then store the accumulator into the PPU
	CPY #$20		; .. compare X to 20 (size of 'palette'), and
	BNE _loop		; loop as long as the Zero flag isn't set (NE)
	.invoke restoreStackReturn
	RTS

	;; Function : backgroundLoad
	;;
	;; Given the address of a set of background tiles, and the
	;; address of their attribute data, load the background into the PPU
	;;
	;; arguments on the stack (in push order):
	;;     - Length of background attribute data
	;;     - Hi byte of background attribute data address
	;;     - Lo byte of background attribute data address
	;;     - Length of background data
	;;     - Hi byte of background data address
	;;     - Lo byte of background data address
backgroundLoad:
	.invoke storeStackReturn
	PLA
	STA curBackgroundLo
	PLA
	STA curBackgroundHi
	PLA
	STA curBackgroundLen
	PLA
	STA curBackgroundAttrLo
	PLA
	STA curBackgroundAttrHi
	PLA
	STA curBackgroundAttrLen
	LDA $2002		; reset the PPU hi/low latch
	LDA #$20
	STA $2006		; PPU address data is written high then low
	LDA #$00
	STA $2006
	LDY #$00
_loadbgloop:
	LDA (curBackgroundLo), y
	STA $2007
	INY
	CPY curBackgroundLen
	BNE _loadbgloop
	
	LDA $2002		; reset the PPU latch again
	LDA #$23
	STA $2006
	LDA #$C0
	STA $2006
	LDY #$00
_loadattrloop:
	LDA (curBackgroundAttrLo), y
	STA $2007
	INY
	CPY curBackgroundAttrLen
	BNE _loadattrloop
	.invoke restoreStackReturn
	RTS
	
	;; Function : oamInsertMultiSprite
	;;
	;; Given the address of a multisprite, and its length (number of
	;; subsprites), load the multisprite into the OAM memory at
	;; index 0.
	;;
	;; Arguments on the stack:
	;;     - Length of multisprite
	;;     - High byte of multisprite's address
	;;     - Low byte of multisprite's address
	;;
	;; FIXME: Need to keep a list of all multisprites so I can append
	;; new ones to the list, and remove dead ones; right now this all
	;; presumes $0200 is the root for the multisprite, which will stop
	;; being true once I have more than one.
oamInsertMultiSprite:
	.invoke storeStackReturn
	LDX #$0
	LDY #$0
	PLA
	STA curSpriteLen
	PLA
	STA curSpriteDataHi
	PLA
	STA curSpriteDataLo
	;; ----
_looptop:
	LDA playery		; set Y position
	CLC
	ADC (curSpriteDataLo), y
	STA (curSpriteOAMIndexLo), y
	INY
	LDA (curSpriteDataLo), y	; set tile number
	STA (curSpriteOAMIndexLo), y
	INY
	LDA (curSpriteDataLo), y
	STA (curSpriteOAMIndexLo), y
	INY
	LDA playerx		; set X position
	CLC
	ADC (curSpriteDataLo), y
	STA (curSpriteOAMIndexLo), y
	INY
	INX			; increment the sprite counter
	CPX curSpriteLen	; any more sprites in the current multisprite?
	BNE _looptop
	.invoke restoreStackReturn
	RTS
