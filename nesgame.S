	;; All NES ROMs have a 16 byte header that describes how the ROM
	;; works; specifically, how many banks of 16kB PRG (program) code,
	;; how many 8kB banks of CHR data, which mapper to use for bank swapping
	;; and how to perform background mirroring

  .inesprg 1		;; 1x 16kB bank of PRG (program) code
  .ineschr 1		;; 1x 8kB bank of CHR (tile/sprite) data
  .inesmap 0		;; use mapper 0; NROM, no bank swapping
  .inesmir 1		;; background mirroring (we don't care for now)

	;; For NESASM, we need to tell it where each bank begins.

  .bank 0
  .org $C000		;; PRG bank 1 has 8kB at 0x0C000

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
	STX $2001		;; set PPU flag to disable rendering (0x2001 = 0)
	STX $4010		;; disable APU IRQs, no audio
_START_vblankwait:
	BIT $2002		;; Bitwise AND the accumulator (LDA) with mem
				;; at 0x2002, and set the Zero, Sign and Overflow
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
	STA sprStartClearing, x	;; OAM; previous tutorial had this at 0300,
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
	;; Let's hit milestone 2 and draw a sprite

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
_MAIN_loop:
	LDX #$0
_MAIN_MoveMarioToPlayer_x:
	LDA playerx
	ADC sprMario_x, x
	STA sprMario_x, x
	INX
	INX
	INX
	INX
	CPX #$20
	BNE _MAIN_MoveMarioToPlayer_x
	LDX #$0
_MAIN_MoveMarioToPlayer_y:
	LDA playery
	ADC sprMario, x
	STA sprMario, x
	INX
	INX
	INX
	INX
	CPX #$20
	BNE _MAIN_MoveMarioToPlayer_y
	JMP _MAIN_loop	 	;; Loop forever

NMI:
	;; We need to copy all our OAM data to put sprites on screen during
	;; vblank. $2003 is the PPU OAM address, so we're going to tell it
	;; to pull OAM from $0200, and do a DMA transfer.
	LDA #$00
	STA $2003
	LDA #$FF
	STA $4014		; 4014 is the OAM_DMA operation, which will
				; do a DMA from the (LDA|$2003) address,
				; for FF bytes (in our case $0200-$02FF),
				; which takes ~513 cycles. An unrolled
				; loop to do the same thing would take
				; 3-4 times as long.
	RTI			; just return
	
  .bank 1		;; NESASM sees our 16kB code banks as pairs of
  .org $E000		;; 8kB code banks, so we have to declare each
			;; 8kB half-bank separately, and split code
			;; between them.
			;; .. How to know when we have written enough
			;; code? ..

palette:
  .db $0F,$31,$32,$33,$0F,$35,$36,$37,$0F,$39,$3A,$3B,$0F,$3D,$3E,$0F
  .db $0F,$1C,$15,$14,$0F,$02,$38,$3C,$0F,$1C,$15,$14,$0F,$02,$38,$3C
playerx:
  .db $01
playery:
  .db $01
playerSprIndex:
  .db $00

	;; I put the OAM copy here instead of $0200 because I want to
	;; allow me to initialize some basic sprite organizations (such as
	;; mario standing) without having to do a bunch of pokes into my
	;; OAM copy, because the only thing that ever actually changes is
	;; the X and Y position. But I couldn't get the NMI copying to work
	;; correctly when trying to set a bank to .org at $0200; I'm probably
	;; just doing it wrong, but for now this works.
  .org $FF00
sprMario:
	;; each 4-byte pair goes directly into the OAM
  .db $10,$00,$00		; mario top left Y,tile,attrs
sprMario_x:
  .db $10			; mario top left X
  .db $10,$01,$00,$18		; mario top right
  .db $18,$02,$00,$10		; mario middle left
  .db $18,$03,$00,$18 		; mario middle right
  .db $20,$04,$00,$10		; mario middle bottom left
  .db $20,$05,$00,$18		; mario middle bottom right
  .db $28,$06,$00,$10		; mario bottom left
  .db $28,$07,$00,$18		; mario bottom right
sprStartClearing:
  .db $00

  .bank 1
  .org $FFFA
  .dw NMI	;; For Non-Maskable Interrupts, please jump to the location
	        ;; of the NMI label
  .dw START 	;; For the reset button or power-on, jump to the location
		;; of the START label
  .dw 0	  	;; If we used an external IRQ vector, we would put it here

	;; --- graphics bank
	
  .bank 2		;; CHR bank 0 starts here for tile/sprite data
  .org $0000		;; CHR data is below PRG data in the memory
  .incbin "mario.chr"	; include 8kB of graphics from SMB1
