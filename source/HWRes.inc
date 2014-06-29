; *** Hardware dependent resident part definition

; --- DMA Descriptor management ---
extern	VTxInProg : word
extern	VTxCopyHead : word
extern	VTxCopyTail : word
extern	VTxHead : word
extern	VTxTail : word
extern	VTxFreeHead : word
extern	VTxFreeTail : word
extern	TxCopySel : word
extern	TxCount : word
extern	TxPageMask : word
extern	TxPageStart : byte

extern	RxPageStart : byte
extern	RxPageStop : byte
extern	RxCurrentPage : byte
extern	RxBoundaryPage : byte
extern	RxCopySel : word
extern	RxLookaheadSize : word
extern	RxRangeLen0 : word
extern	RxRangeLen1 : word
extern	RxRangeAddr1 : word
extern	RxRangeLen2 : word
extern	RxRangeAddr2 : word
extern	RxStatus : byte
extern	RxNextPtr : byte
extern	RxLength : word
extern	RxBuffer : byte


; --- System(PCI) Resource ---
extern	IOaddr : word
;extern	MEMSel : word		; selector for MEMaddr
;extern	MEMaddr : dword
extern	IRQlevel : byte

; --- Configuration Memory Image Parameters ---
extern	cfgIOBASE : word
extern	cfgIRQLevel : byte
extern	cfgTXQUEUE : byte
extern	cfgRXQUEUE : byte
extern	cfgVTXQUEUE : byte
extern	cfgMAXFRAMESIZE : word



; ---Vendor Adapter Description ---
extern	AdapterDesc : byte


; --- Hardware Depended Services ---
extern	_hwTxChain : near16
;extern	_hwRxRelease : near16
extern	_hwRxTransfer : near16
extern	_hwEnableRxInd : near16
extern	_hwDisableRxInd : near16
extern	_hwSetMACaddr : near16
extern	_hwOpen : near16
extern	_hwClose : near16
extern	_hwIntReq : near16
extern	_hwUpdatePktFlt : near16
extern	_hwUpdateMulticast : near16
extern	_hwSetLookahead : near16
extern	_hwUpdateStat : near16
extern	_hwClearStat : near16
extern	_hwReset : near16

extern	_hwCheckInt : near16
extern	_hwDisableInt : near16
extern	_hwEnableInt : near16
extern	_hwServiceInt : near16
extern	_hwPollLink : near16


; --- Driver Version ---
extern	DrvMajVer : abs
extern	DrvMinVer : abs

