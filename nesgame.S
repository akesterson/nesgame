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

  .include "defines.S"
	
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
  .space curSpriteOAMIndexLo 1
  .space curSpriteOAMIndexHi 1
  .space curSpriteDataLo 1
  .space curSpriteDataHi 1
  .org $0020
	;; $0020 - 00FF is space for general purpose global variables
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

  .text
  .org $C000		;; PRG bank code starts at 0xC000

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

MAIN:
	;; horray, here is main()
_MAIN_LoadPalettes:
	LDA $2002		; The PPU Memory address at $2006 expects
				; the high byte of the palette address first,
				; then the low byte, but we can't know
				; which one it's expecting right now, so we
				; read the PPU status at $2002 to reset the
				; high/low latch on $2006.
	LDA #$3F		; we're populating the second palette, at $3F10
	STA $2006
	LDA #$00
	STA $2006
	LDX #$00
_MAIN_LoadPaletteLoop:
	LDA palette, x		; Loop over each index of the byte array at
	STA $2007		; 'palette', store each one into the accumulator
	INX			; and then store the accumulator into the PPU
	CPX #$20		; .. compare X to 20 (size of 'palette'), and
	BNE _MAIN_LoadPaletteLoop ; loop as long as the Zero flag isn't set (NE)
	

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

	;; All the sprite OAM data is initialized at the bottom of bank 1
	;; at .org $FF00
	
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

	LDA #%10000000		; enable NMI (so we get a function call every
				; vblank), and draw sprites from table 0
	STA $2000

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

	LDA #%00010000		;; turn on sprites, no more background color
	STA $2001		;; Write to PPU Control Register 2
	LDX #$0

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

_MAIN_loop:
	JMP _MAIN_loop	 	;; Loop forever

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
	RTI			; just return

palette:
  .byte $0F,$31,$32,$33,$0F,$35,$36,$37,$0F,$39,$3A,$3B,$0F,$3D,$3E,$0F
  .byte $0F,$1C,$15,$14,$0F,$02,$38,$3C,$0F,$1C,$15,$14,$0F,$02,$38,$3C
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
