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
	STA $0200, x		;; 
	STA $0400, x		;; for ( x = 0; x < 256 ; x++)
	STA $0500, x		;;    *(0x0100 + x) = 0;
	STA $0600, x		;;    ....
	STA $0700, x		;; the INX and BNE at the bottom are the "; x++)"
				;; This clears the zero page, the stack, and
				;; the entirety of main RAM

	LDA #$FE		;; It's also not clear at all what these two
	STA $0300, x		;; are setting; maybe it's object attribute
				;; memory (OAM)?

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
	;; all we do is set the PPU mask to intensify blues, and loop forever

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

	LDA #%10000000		;; blue background!
	STA $2001		;; Write to PPU Control Register 2
_MAIN_loop:	
	JMP _MAIN_loop	 	;; Loop forever and do nothing

NMI:
	RTI			; just return
	
  .bank 1		;; NESASM sees our 16kB code banks as pairs of
  .org $E000		;; 8kB code banks, so we have to declare each
			;; 8kB half-bank separately, and split code
			;; between them.
			;; .. How to know when we have written enough
			;; code? ..
	
	;; insert the rest of the bank 1 code here

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
