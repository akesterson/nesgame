  .alias curSpriteDataRead curSpriteDataLo
  .alias curSpriteDataWrite curSpriteDataHi
  .alias pada %10000000
  .alias padb %01000000
  .alias padselect %00100000
  .alias padstart %00010000
  .alias padup %00001000
  .alias paddown %00000100
  .alias padleft %00000010
  .alias padright %00000001

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
