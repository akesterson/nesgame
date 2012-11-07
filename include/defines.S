  .alias curSpriteDataRead curSpriteDataLo
  .alias curSpriteDataWrite curSpriteDataHi

.macro storeStackReturn 	; storeStackReturn
	PLA
	STA prevReturnAddrHi
	PLA
	STA prevReturnAddrLo
.macend

.macro restoreStackReturn
	LDA prevReturnAddrLo
	PHA
	LDA prevReturnAddrhi
	PHA
.macend