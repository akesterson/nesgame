	;; Function : divide
	;;
	;; Divide the value in A by the value in Y
	;; The dividend is returned in A
	;; The modulus is returned in Y
divide:
	.invoke storeStackReturn
        sta tempdivident        ;Stores divident
	sty tempdivisor	        ;Stores divisor
	lda #$00
	sta tempdivresult         ;Clear result

	ldy #$10        	;The loop is for 16-bit result
_divide_loop:
	asl tempdivident
	rol			;Shift divisor in 1 bit
	cmp tempdivisor         ;Check if fractional dividend is greater than divisor
	bcc _divide_subloop
	sbc tempdivisor 	;Substract (C is always set)
_divide_subloop:
	rol tempdivresult	;Shift result (1 if substation was done, 0 otherwise)
	rol tempdivmodulus
	dey
	bne _divide_loop
	lda tempdivresult
	ldy tempdivmodulus
	.invoke restoreStackReturn
	RTS
