	;; All NES ROMs have a 16 byte header that describes how the ROM
	;; works; specifically, how many banks of 16kB PRG (program) code,
	;; how many 8kB banks of CHR data, which mapper to use for bank swapping
	;; and how to perform background mirroring

	;; iNES header block
	
  .byte "NES",$1A
  .byte $01		;; 1 PRG ROM page (how big is an ophis page?)
  .byte $02		;; 1 CHR (tile/sprite) ROM page (how big is a page?)
  .byte $00		; Horizontal mirroring
  .byte $00		; Mapper 0 (NROM, no bank switching)
  .byte $00,$00,$00,$00	; Reserved bytes
  .byte $00,$00,$00,$00 ; Reserved bytes

  .require "include/defines.S"
	
  .text zp
  .org $0000
	;; $0000 is reserved for things we use to extend PL/PH for call/return stacks
	;; FIXME: Will need to expand this stuff once I start calling 2+
	;; functions at once; e.g., JSR a -> JSR b -> JSR c...
	;; will need to expand it to a real stack.
  .space prevReturnAddrLo 1
  .space prevReturnAddrHi 1
  .org $0010
	;; $0010 - 001F is reserved for global pointers
  .space curPaletteLo	1
  .space curPaletteHi 1
  .space curSpriteOAMIndexLo 1
  .space curSpriteOAMIndexHi 1
  .space curBackgroundLo 1
  .space curBackgroundHi 1
  .space curBackgroundAttrLo 1
  .space curBackgroundAttrHi 1
  .space curSpriteDataLo 1
  .space curSpriteDataHi 1
  .org $0020
	;; $0020 - 00FF is space for general purpose global variable
  .space curBackgroundLen 1
  .space curBackgroundAttrLen 1
  .space curSpriteLen	1
  .space playery	1
  .space playerx	1
  .space pad1a		1
  .space pad1b		1
  .space pad1select	1
  .space pad1start	1
  .space pad1up		1
  .space pad1down	1
  .space pad1left	1
  .space pad1right	1
  .space pad1areleased	1
  .space multiSpriteList 16 	; reserve 6 words for the list of multisprites
				; currently on screen, each one listed as a
				; WORD address
  .space tempdivident 1
  .space tempdivisor 1
  .space tempdivresult 1
  .space tempdivmodulus 1

  .text
  .org $C000		;; PRG bank code starts at 0xC000

  .require "include/math.S"
  .require "include/graphics.S"

	;; START will be called by the NES whenever the system boots
	;; or when the reset button is pressed (think of _start in libc )
	;; but the fact that the NES looks at "START" is only because we
	;; specified it in bank 1 at 0xFFFA, the vector table
START:
	SEI			;; disable IRQs (we don't have an IRQ vector)
	CLD			;; disable decimal mode (NES 6502 doesn't have
				;; a decimal mode, please don't produce decimal
				;; mode instructions, NESASM!)
	LDX #$40		;; load 0x40 into X register
	STX $4017		;; store what's in X to address 0x4017 ...
				;; 0x4017 is the Joystick 2 port?! WTF does this
				;; do?!
	LDX #$FF
	TXS			;; Move the contents of X to the stack pointer
	INX			;; increment X by 1, which causes overflow, so
				;; now X is 0
	
	STX $2000		;; set PPU flag to disable NMI (0x2000 = 0)
	STX $2001		;; set PPU flag to disable rendering (0x2001=0)
	STX $4010		;; disable APU IRQs, no audio
_START_vblankwait:
	BIT $2002		;; Bitwise AND the accumulator (LDA) with mem
				;; at 0x2002, and set the Zero, Sign & Overflow
				;; flags accordingly. 0x2002 is the PPU status
				;; register; when 0x2002 has bit 7 set, we are
				;; in vblank, so this is how we check for it.
	BPL _START_vblankwait	;; Until the sign bit is set, loop here. Wait
				;; for vblank.

_START_clearmem:
				;; Hey look, it's the longest memset() ever!
	LDA #$00
	STA $0000, x		;; store 0 to (LDX) + 0x0000 ... but X should
				;; be 0 at this point (see START where we INX),
				;; so why aren't we just using zero-page
				;; addressing?
				;; ... that's what I thought at first, before
	STA $0100, x		;; I realized that I'm looking at a loop:
	STA $0200, x
	STA $0400, x		;; for ( x = 0; x < 256 ; x++)
	STA $0500, x		;;    *(0x0100 + x) = 0;
	STA $0600, x		;;    ....
	STA $0700, x		;; the INX and BNE at the bottom are the "; x++)"
				;; This clears the zero page (0000-00FF, the
				;; stack (0100-01FF), the entirety of main RAM
				;; (0200-07FF)

	LDA #$FE		;; These two are clearing all of the sprite 
	STA $0200, x		;; OAM; previous tutorial had this at 0300,
				;; which may have been wrong. We don't HAVE
				;; to reserve this range for OAM; we could
				;; just manually poke bits into the PPU, but
				;; that is 3-4x (or more) slower than reserving
				;; 256 bytes for an OAM copy that we DMA into
				;; the PPU on every vblank/NMI

	INX			;; X is already 0 so this should do X=1,
				;; and the Zero and Sign flags should both go 0
	BNE _START_clearmem	;; "; x++)", loop back to clrmem until X rolls

_START_vblankwait2:
	BIT $2002		;; copy paste going to happen in ASM
	BPL _START_vblankwait2	;; once we've gotten 1 vblank,
				;; cleared mem, and gotten another vblank,
				;; the PPU is ready. Wait for it.
	JMP main	
	
	
main:
	;; horray, here is main()
	LDA #$00
	PHA
	LDA #<palette
	PHA
	LDA #>palette
	PHA
	JSR paletteLoad
	;; $2000 is the PPU Control register, controlled by various bitflags.
	;; 
	;; 7654 3210
	;; |||| ||||
	;; |||| ||++- Base nametable address
	;; |||| ||    (0 = $2000; 1 = $2400; 2 = $2800; 3 = $2C00)
	;; |||| |+--- VRAM address increment per CPU read/write of PPUDATA
	;; |||| |     (0: increment by 1, going across;
	;; |||| |      1: increment by 32, going down)
	;; |||| +---- Sprite pattern table address for 8x8 sprites
	;; ||||       (0: $0000; 1: $1000; ignored in 8x16 mode)
	;; |||+------ Background pattern table address (0: $0000; 1: $1000)
	;; ||+------- Sprite size (0: 8x8; 1: 8x16)
	;; |+-------- PPU master/slave select (has no effect on the NES)
	;; +--------- Generate an NMI at the start of the
	;;            vertical blanking interval (0: off; 1: on)


	;; The PPU mask is set at $2001, the 2nd PPU Control register, and it
	;; sets one config option for every bit of the byte
	;; 
	;; 76543210
	;; ||||||||
	;; |||||||+- Grayscale (0: normal color; 1: AND all palette entries
	;; |||||||   with 0x30, effectively producing a monochrome display;
	;; |||||||   note that colour emphasis STILL works when this is on!)
	;; ||||||+-- Disable background clipping in leftmost 8 pixels of screen
	;; |||||+--- Disable sprite clipping in leftmost 8 pixels of screen
	;; ||||+---- Enable background rendering
	;; |||+----- Enable sprite rendering
	;; ||+------ Intensify reds (and darken other colors)
	;; |+------- Intensify greens (and darken other colors)
	;; +-------- Intensify blues (and darken other colors)

	
	LDA #$80
	STA playerx
	STA playery
	;; Put mario in as the first multisprite
	LDA #<sprMarioData
	PHA
	LDA #>sprMarioData
	PHA
	LDA sprMario
	PHA
	;; DO IT
	LDA #$00
	STA curSpriteOAMIndexLo
	LDA #$02
	STA curSpriteOAMIndexHi
	JSR oamInsertMultiSprite
	;;  ----------------------------------
	LDA #$20
	STA playerx
	LDA #$20
	STA playery
	LDA #<sprMario2Data
	PHA
	LDA #>sprMario2Data
	PHA
	LDA sprMario2
	PHA
	LDA #$40
	STA curSpriteOAMIndexLo
	LDA #$02
	STA curSpriteOAMIndexHi
	JSR oamInsertMultiSprite
	;; ---------------------------
_bgcall:
	LDA bgattrsize
        PHA
        LDA #>backgroundattrs
        PHA
        LDA #<backgroundattrs
        PHA
	LDA bgsize
	PHA
        LDA #>background
        PHA
        LDA #<background
        PHA
        JSR backgroundLoad

	;; Apparently you do NOT set sprite and tile data while these are turned on, bad things
	;; will happen!
	LDA #%10010000		; enable NMI (so we get a function call every
				; vblank), and draw sprites from table 0
	STA $2000
	LDA #%10011110		;; turn on sprites, turn on background, don't clip on the left
	STA $2001		;; Write to PPU Control Register 2
	LDA #$00		; hey PPU, stop friggin scrolling!
	STA $2005
	STA $2005
	LDX #$0

_MAIN_loop:
	JMP _MAIN_loop	 	;; Loop forever

NMI:	
	;; We need to copy all our OAM data to put sprites on screen during
	;; vblank. $2003 is the PPU OAM address, so we're going to tell it
	;; to pull OAM from $0200, and do a DMA transfer.
	LDA #$00
	STA $2003
	LDA #$02
	STA $4014		; 4014 is the OAM_DMA operation, which will
				; do a DMA from the (LDA|$2003) address,
				; for FF bytes (in our case $0200-$02FF),
				; which takes ~513 cycles. An unrolled
				; loop to do the same thing would take
				; 3-4 times as long.
	LDA #%10010000		; enable NMI (so we get a function call every
				; vblank), and draw sprites from table 0
	STA $2000
	LDA #%00011110		;; turn on sprites, turn on background, don't clip on the left
	STA $2001		;; Write to PPU Control Register 2
	LDA #$00		; hey PPU, stop friggin scrolling!
	STA $2005
	STA $2005
	RTI			; just return

palette:
  .byte $22,$29,$1A,$0F,$22,$36,$17,$0F,$22,$30,$21,$0F,$22,$27,$17,$0F   ;;background palette
  .byte $22,$1C,$15,$14,$22,$02,$38,$3C,$22,$1C,$15,$14,$22,$02,$38,$3C   ;;sprite palette
bgsize:
  .byte $80
bgattrsize:
  .byte $08
background:
  .byte $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24  ;;row 1
  .byte $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24  ;;all sky
  .byte $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24  ;;row 2
  .byte $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24  ;;all sky
  .byte $24,$24,$24,$24,$45,$45,$24,$24,$45,$45,$45,$45,$45,$45,$24,$24  ;;row 3
  .byte $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$53,$54,$24,$24  ;;some brick tops
  .byte $24,$24,$24,$24,$47,$47,$24,$24,$47,$47,$47,$47,$47,$47,$24,$24  ;;row 4
  .byte $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$55,$56,$24,$24  ;;brick bottoms
backgroundattrs:
  .byte %00000000,%00010000,%01010000,%00010000
  .byte %00000000,%00000000,%00000000,%00110000
  .byte $24,$24,$24,$24
  .byte $47,$47,$24,$24
  .byte $47,$47,$47,$47
  .byte $47,$47,$24,$24
  .byte $24,$24,$24,$24
  .byte $24,$24,$24,$24
  .byte $24,$24,$24,$24
  .byte $55,$56,$24,$24  ;;brick bottoms

	;; All sprites live between 0200-02FF; there are a max of 64 sprites
	;; on screen, and each one has a 4 byte struct describing it.
	;; *(sprite + 0) = y position
	;; *(sprite + 1) = tile index (0-FF) in the pattern table for pixels
	;; *(sprite + 2) = attributes. Color palette, priority, and mirroring.
	;;  76543210
	;;  |||   ||
	;;  |||   ++- Color Palette of sprite.  Choose which set of 4 from
	;;  |||       	the 16 colors to use. You can select sprite colors only
	;;  |||		in groups of 4 on 4 byte boundaries; so you can select
	;;  |||		colors 0-3, 4-7, 8-11, and 12-15, but not 2-5, for
	;;  |||		example. Palette construction and use is an art in
	;;  |||		itself!
	;;  |||
	;;  ||+------ Priority (0: in front of background; 1: behind background)
	;;  |+------- Flip sprite horizontally
	;;  +-------- Flip sprite vertically
	;; *(sprite + 3) = x position

sprMario:
  .byte $08 			; Total number of subsprites in this metasprite
sprMarioData:
  ;;  Y, Tile, Atr, X
  .byte $00,$00,$00,$00
  .byte $00,$01,$00,$08
  .byte $08,$02,$00,$00
  .byte $08,$03,$00,$08
  .byte $10,$04,$00,$00
  .byte $10,$05,$00,$08
  .byte $18,$06,$00,$00
  .byte $18,$07,$00,$08

sprMario2:
  .byte $08 			; Total number of subsprites in this metasprite
sprMario2Data:
  ;;  Y, Tile, Atr, X
  .byte $00,$08,$00,$00
  .byte $00,$09,$00,$08
  .byte $08,$0A,$00,$00
  .byte $08,$0B,$00,$08
  .byte $10,$0C,$00,$00
  .byte $10,$0D,$00,$08
  .byte $18,$0E,$00,$00
  .byte $18,$0F,$00,$08

  .advance $FFFA
  .word NMI	;; For Non-Maskable Interrupts, please jump to the location
	        ;; of the NMI label
  .word START 	;; For the reset button or power-on, jump to the location
		;; of the START label
  .word 0  	;; If we used an external IRQ vector, we would put it here

	;; --- graphics bank
	
  .org $0000		;; CHR data is below PRG data in the memory
  .incbin "mario.chr"	; include 8kB of graphics from SMB1
