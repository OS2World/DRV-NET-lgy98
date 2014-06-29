; *** Resident part: Hardware dependent ***

include	NDISdef.inc
include	lgy98.inc
include	MIIdef.inc
include	misc.inc
include	DrvRes.inc

extern	DosIODelayCnt : far16

public	DrvMajVer, DrvMinVer
DrvMajVer	equ	1
DrvMinVer	equ	0

.386

_DATA	segment	public word use16 'DATA'

; --- DMA Descriptor management ---
public	VTxInProg, VTxCopyHead, VTxCopyTail
public	VTxHead, VTxTail, VTxFreeHead, VTxFreeTail
public	TxCopySel, TxCount, TxPageMask, TxPageStart
VTxInProg	dw	0
VTxCopyHead	dw	0
VTxCopyTail	dw	0
VTxHead		dw	0
VTxTail		dw	0
VTxFreeHead	dw	0
VTxFreeTail	dw	0
TxCopySel	dw	0
TxCount		dw	2
TxPageMask	dw	0
TxPageStart	db	40h,46h,0,0


public	RxPageStart, RxPageStop, RxCurrentPage, RxBoundaryPage ; << debug >>
public	RxCopySel, RxLookaheadSize
public	RxRangeLen0, RxRangeLen1, RxRangeAddr1
public	RxRangeLen2, RxRangeAddr2 	; << debug >>
public	RxStatus, RxNextPtr, RxLength, RxBuffer ; << debug >>
RxPageStart	db	4ch
RxPageStop	db	80h
RxCurrentPage	db	4ch
RxBoundaryPage	db	7fh

RxCopySel	dw	0
RxLookaheadSize	dw	64
RxRangeLen0	dw	0
RxRangeAddr1	dw	0
RxRangeLen1	dw	0
RxRangeAddr2	dw	0
RxRangeLen2	dw	0

RxHead		label	RxHeader
RxStatus	db	?
RxNextPtr	db	?
RxLength	dw	?
RxBuffer	db	256 dup (?)


; --- System(PCI) Resource ---
public	IOaddr, IRQlevel
IOaddr		dw	?
;MEMSel		dw	?
;MEMaddr		dd	?
IRQlevel	db	?

align	2
; --- Physical information ---
;PhyInfo		_PhyInfo <>

;public	MediaSpeed, MediaDuplex, MediaPause, MediaLink	; << for debug >>
;MediaSpeed	db	0
;MediaDuplex	db	0
;MediaPause	db	0
;MediaLink	db	0

; --- Register Contents ---
public	regIntStatus, regIntMask	; << for debug info >>
public	regReceiveMode, regHashTable

regIntStatus	db	0
regIntMask	db	0
regHashTable	dw	4 dup (0)
regReceiveMode	db	0

; --- ReceiveChain Frame Descriptor ---
;public	RxDesc		; << for debug info >>
;RxDesc		RxFrameDesc	<>


; --- Configuration Memory Image Parameters ---
public	cfgIOBASE, cfgIRQLevel
public	cfgTXQUEUE, cfgRXQUEUE, cfgVTXQUEUE
public	cfgMAXFRAMESIZE
cfgIOBASE	dw	0d0h
cfgIRQLevel	db	3

cfgTXQUEUE	db	2
cfgRXQUEUE	db	8
cfgVTXQUEUE	db	6


cfgMAXFRAMESIZE	dw	1514

; --- Receive Buffer address ---
;public	RxBufferLin, RxBufferPhys, RxBufferSize, RxBufferSelCnt, RxBufferSel
;RxBufferLin	dd	?
;RxBufferPhys	dd	?
;RxBufferSize	dd	?
;RxBufferSelCnt	dw	?
;RxBufferSel	dw	6 dup (?)	; max is 6.

; ---Vendor Adapter Description ---
public	AdapterDesc
AdapterDesc	db	'MELCO LGY-98.',0


_DATA	ends

_TEXT	segment	public word use16 'CODE'
	assume	ds:_DATA
	
; USHORT hwTxChain(TxFrameDesc *txd, USHORT rqh, USHORT pid)
_hwTxChain	proc	near
	push	bp
	mov	bp,sp
	push	fs
	lfs	si,[bp+4]
	mov	dx,fs:[si].TxFrameDesc.TxImmedLen
	mov	cx,fs:[si].TxFrameDesc.TxDataCount
	dec	cx
	jl	short loc_2	; no immediate data
loc_1:
	add	dx,fs:[si].TxFrameDesc.TxBufDesc1.TxDataLen
	add	si,sizeof(TxBufDesc)
	dec	cx
	jge	short loc_1
loc_2:
	cmp	dx,cfgMAXFRAMESIZE	; length > 1514 - invalid parameter
	mov	ax,INVALID_PARAMETER
	ja	short loc_ip

	push	offset semTx
	call	_EnterCrit
	mov	bx,[VTxFreeHead]
	or	bx,bx			; unavailable vtxd - out of resource
	jnz	short loc_3
	call	_LeaveCrit
	pop	cx	; stack adjust
	mov	ax,OUT_OF_RESOURCE
loc_ip:
	pop	fs
	pop	bp
	retn

loc_3:
	mov	ax,[bx].vtxd.vlink
	mov	[VTxFreeHead],ax
	call	_LeaveCrit

	mov	cx,[bp+8]
	mov	si,[bp+10]
	mov	bp,[bp+4]
	mov	[bx].vtxd.framelen,dx
	mov	[bx].vtxd.reqhandle,cx
	mov	[bx].vtxd.protid,si

	mov	ax,ds
	mov	es,ax
	mov	cx,fs:[bp].TxFrameDesc.TxImmedLen
	lea	di,[bx].vtxd.txbd
	or	cx,cx
	setnz	[bx].vtxd.cnt
	jz	short loc_4		; no immediate data
	push	ax		; ds
	push	di
	lea	si,[bx].vtxd.immedbuf
	mov	[di].TxBufDesc.TxPtrType,2	; GDT
	mov	[di].TxBufDesc.TxDataLen,cx
	mov	word ptr [di].TxBufDesc.TxDataPtr,si
	mov	word ptr [di].TxBufDesc.TxDataPtr[2],ax
	lds	di,fs:[bp].TxFrameDesc.TxImmedPtr
	mov	ax,cx
	xchg	si,di
	shr	cx,2
	and	al,3
	rep	movsd
	mov	cl,al
	rep	movsb
	pop	di
	pop	ds
	add	di,sizeof(TxBufDesc)
loc_4:
	mov	cx,fs:[bp].TxFrameDesc.TxDataCount
	cmp	[bx].vtxd.framelen,60
	jc	short loc_pad		; pad require. copy all data.
	add	[bx].vtxd.cnt,cl
	lea	si,[bp].TxFrameDesc.TxBufDesc1
	shl	cx,(3-2)		; 8bytes
	rep	movsd	es:[di],fs:[si]
;	jmp	short loc_5
	jmp	near ptr loc_5

loc_pad:
	test	[bx].vtxd.cnt,1
	lea	di,[bx].vtxd.immedbuf
	jz	short loc_p1		; no immediate
	add	di,[bx].vtxd.txbd.TxDataLen
	jmp	short loc_p2
loc_p1:
	mov	[bx].vtxd.txbd.TxPtrType,2	; GDT
	mov	word ptr [bx].vtxd.txbd.TxDataPtr,di
	mov	word ptr [bx].vtxd.txbd.TxDataPtr[2],ds
	mov	[bx].vtxd.cnt,1

loc_p2:
	jcxz	short loc_p6		; immediate only
	mov	dx,cx
	push	gs
	push	offset semTx
	call	_EnterCrit		; protect TxCopySel
loc_p3:
	cmp	fs:[bp].TxFrameDesc.TxBufDesc1.TxPtrType,0
	mov	cx,fs:[bp].TxFrameDesc.TxBufDesc1.TxDataLen
	jz	short loc_p4		; physical address
	lgs	si,fs:[bp].TxFrameDesc.TxBufDesc1.TxDataPtr
	jmp	short loc_p5
loc_p4:
	push	cx
	push	fs:[bp].TxFrameDesc.TxBufDesc1.TxDataPtr
	push	[TxCopySel]
	call	_PhysToGDT
	pop	gs
	xor	si,si
	sub	sp,4+2
loc_p5:
	mov	ax,cx
	add	bp,sizeof(TxBufDesc)
	shr	cx,2
	and	al,3
	rep	movsd	es:[di],gs:[si]
	mov	cl,al
	dec	dx
	rep	movsb	es:[di],gs:[si]
	jnz	short loc_p3
	call	_LeaveCrit
	pop	ax	; stack adjust
	pop	gs
loc_p6:
	mov	cx,60
	mov	dx,[bx].vtxd.framelen
	mov	[bx].vtxd.framelen,cx
	mov	[bx].vtxd.txbd.TxDataLen,cx
	sub	cx,dx
	xor	eax,eax
	mov	dx,cx
	and	cx,3
	shr	dx,2
	rep	stosb
	mov	cx,dx
	rep	stosd

loc_5:				; put into remote DMA waiting queue
	call	_EnterCrit
	xor	ax,ax
	mov	[bx].vtxd.vlink,ax
	cmp	ax,[VTxHead]
	jnz	short loc_6
	mov	[VTxHead],bx
	jmp	short loc_7
loc_6:
	mov	si,[VTxTail]
	mov	[si].vtxd.vlink,bx
loc_7:
	mov	[VTxTail],bx
	call	_LeaveCrit
	call	_TxRemoteDMA
	pop	cx	; stack adjust
	mov	ax,REQUEST_QUEUED
	pop	fs
	pop	bp
	retn
_hwTxChain	endp

_TxRemoteDMA	proc	near
	push	offset semTx
	call	_EnterCrit
	mov	di,[VTxHead]
	or	di,di
	jz	short loc_f		; no waiting frame
	mov	bx,[TxCount]
	mov	ax,[TxPageMask]
	dec	bx
loc_1:
	bts	ax,bx
	jnc	short loc_2		; free remote address found
	dec	bx
	jge	short loc_1
loc_f:
	call	_LeaveCrit
	pop	bx	; stack adjust
	xor	ax,ax
	retn

loc_2:
	mov	cl,[TxPageStart][bx]
	mov	[TxPageMask],ax
	mov	dx,[IOaddr]
	mov	[di].vtxd.startpage,cl
	mov	ax,[di].vtxd.framelen
	mov	bl,[di].vtxd.cnt
	inc	ax
	add	dx,RBCR0
	add	di,offset vtxd.txbd
	and	al,-2

	push	offset semReg
	call	_EnterCrit
	out	dx,al
	mov	al,ah
	inc	dx
	out	dx,al		; Remote Byte Count
	mov	al,0
	add	dx,RSAR0 - RBCR1
	out	dx,al
	mov	al,cl
	inc	dx
	out	dx,al		; Remote Start Address
	mov	al,STA or RD1
	add	dx,CR - RSAR1
	out	dx,al		; remote DMA write command
	add	dx,DataPort - CR
	xor	ax,ax
loc_3:
	cmp	[di].TxBufDesc.TxPtrType,0
	mov	cx,[di].TxBufDesc.TxDataLen
	jz	short loc_4		; physical
	les	si,[di].TxBufDesc.TxDataPtr
	jmp	short loc_5
loc_4:
	push	cx
	push	[di].TxBufDesc.TxDataPtr
	push	[TxCopySel]
	call	_PhysToGDT
	pop	es
	xor	si,si
	add	sp,4+2
loc_5:
	test	ah,ah		; overflowed byte?
	jz	short loc_6
	dec	cx
	mov	ah,es:[si]
	inc	si
	out	dx,ax
loc_6:
	shr	cx,1
	rep	outsw dx,es:[si]
	setc	ah
	jnc	short loc_7
	mov	al,es:[si]
loc_7:
	add	di,sizeof(TxBufDesc)
	dec	bl
	jnz	short loc_3
	test	ah,ah
	jz	short loc_8
	out	dx,ax		; frame tail byte is overflowed.
loc_8:
	add	dx,CR - DataPort
	mov	bx,offset DosIODelayCnt
loc_rdw:
	in	al,dx
	test	al,RD2
	jnz	short loc_rdc	; remote DMA complete
	dec	bx
	jnz	short loc_rdw	; timeout?
loc_rdc:
;	xor	cx,cx		; already zero
	mov	di,[VTxHead]
	mov	ax,[di].vtxd.vlink
	mov	[di].vtxd.vlink,cx
	mov	[VTxHead],ax
	cmp	cx,[VTxCopyHead]
	jnz	short loc_9
	mov	[VTxCopyHead],di
	jmp	short loc_10
loc_9:
	mov	si,[VTxCopyTail]
	mov	[si].vtxd.vlink,di
loc_10:
	cmp	cx,[VTxInProg]
	mov	[VTxCopyTail],di
	jnz	short loc_11		; transmit in progress

	mov	bx,[VTxCopyHead]
	add	dx,TPSR - CR
	mov	si,[bx].vtxd.vlink
	mov	al,[bx].vtxd.startpage
	mov	[VTxInProg],bx
	mov	[VTxCopyHead],si
	out	dx,al			; tx start page
	mov	ax,[bx].vtxd.framelen
	inc	dx
	out	dx,al
	mov	al,ah
	inc	dx
	out	dx,al			; tx frame length
	mov	al,STA or TXP or RD2
	add	dx,CR - TBCR1
	out	dx,al			; tx command
loc_11:
	call	_LeaveCrit
	pop	ax
	call	_LeaveCrit
	pop	bx

	mov	ax,1
	retn
_TxRemoteDMA	endp



; USHORT hwRxTransfer( TDFrameDesc *tdd, USHORT len, USHORT *bc )
_hwRxTransfer	proc	near
	enter	10,0
rxt_tlen	equ	bp-10
rxt_dlen	equ	bp-8
rxt_slen	equ	bp-6
rxt_rng		equ	bp-4
rxt_cnt		equ	bp-2

	push	fs
	lfs	bx,[bp+4]
	xor	ax,ax
	mov	cx,fs:[bx].TDFrameDesc.TDDataCount
	mov	byte ptr [rxt_rng],al
	mov	[rxt_dlen],ax
	mov	[rxt_tlen],ax
	add	bx,offset TDFrameDesc.TDBufDesc1
	mov	ax,[bp+8]
	mov	[rxt_cnt],cx

	cmp	ax,[RxRangeLen0]
	jnc	short loc_1	; over lookahead buffer
	mov	si,offset RxBuffer
	mov	cx,[RxRangeLen0]
	jmp	short loc_3

loc_ip:
	mov	ax,INVALID_PARAMETER
	pop	fs
	retn

loc_1:
	sub	ax,[RxRangeLen0]
	inc	byte ptr [rxt_rng]
	cmp	ax,[RxRangeLen1]
	jnc	short loc_2	; over first fragment
	mov	si,[RxRangeAddr1]
	mov	cx,[RxRangeLen1]
	jmp	short loc_3

loc_2:
	sub	ax,[RxRangeLen1]
	inc	byte ptr [rxt_rng]
	mov	si,[RxRangeAddr2]
	mov	cx,[RxRangeLen2]
loc_3:
	sub	cx,ax
	jna	short loc_ip	; start offset >= frame length
	add	si,ax
	push	offset semReg
	xor	ax,ax
	call	_EnterCrit
loc_4:
	mov	[rxt_slen],cx
	cmp	byte ptr [rxt_rng],0
	jz	short loc_5
	push	ax		; reserve overflowed byte, flag
	mov	dx,[IOaddr]
	mov	ax,cx
	add	dx,RBCR0
	out	dx,al
	mov	al,ah
	inc	dx
	out	dx,al
	mov	ax,si
	add	dx,RSAR0 - RBCR1
	out	dx,al
	mov	al,ah
	inc	dx
	out	dx,al
	mov	al,STA or RD0
	add	dx,CR - RSAR1
	out	dx,al
	add	dx,DataPort - CR
	pop	ax

loc_5:
	mov	cx,word ptr [rxt_dlen]
	or	cx,cx
	jnz	short loc_7

	dec	word ptr [rxt_cnt]
;	jl	short loc_13
	jl	near ptr loc_13
	cmp	fs:[bx].TDBufDesc.TDPtrType,0
	mov	cx,fs:[bx].TDBufDesc.TDDataLen
	jz	short loc_6
	les	di,fs:[bx].TDBufDesc.TDDataPtr
	jmp	short loc_7
loc_6:
	push	cx
	push	fs:[bx].TDBufDesc.TDDataPtr
	push	[RxCopySel]
	call	_PhysToGDT
	pop	es
	xor	di,di
	add	sp,4+2
loc_7:
	mov	[rxt_dlen],cx
	add	bx,sizeof(TDBufDesc)
	cmp	cx,[rxt_slen]
	jb	short loc_8
	mov	cx,[rxt_slen]
loc_8:
	sub	[rxt_dlen],cx
	sub	[rxt_slen],cx
	add	[rxt_tlen],cx
	test	ah,ah
	jz	short loc_9
	stosb
	dec	cx
loc_9:
	cmp	byte ptr [rxt_rng],0
	jnz	short loc_91
	mov	ax,cx
	shr	cx,2
	and	ax,3
	rep	movsd
	mov	cl,al
	rep	movsb
	xor	ax,ax
	jmp	short loc_11

loc_91:
	shr	cx,1
	rep	insw
	jnc	short loc_10
	in	ax,dx
	stosb
	mov	al,ah
loc_10:
	setc	ah
loc_11:
	cmp	word ptr [rxt_slen],0
	jnz	short loc_5
	cmp	byte ptr [rxt_rng],1
	jz	short loc_12
	ja	short loc_13
	mov	si,[RxRangeAddr1]
	mov	cx,[RxRangeLen1]
	inc	byte ptr [rxt_rng]
	or	cx,cx
;	jnz	short loc_4
	jnz	near ptr loc_4
loc_12:
	mov	si,[RxRangeAddr2]
	mov	cx,[RxRangeLen2]
	inc	byte ptr [rxt_rng]
	or	cx,cx
;	jnz	short loc_4
	jnz	near ptr loc_4
loc_13:
	add	dx,CR - DataPort
	mov	al,STA or RD2
	out	dx,al		; stop remote DMA
	mov	al,0
	add	dx,RBCR0 - CR
	out	dx,al
	inc	dx
	out	dx,al
	call	_LeaveCrit
	pop	ax

	mov	cx,[rxt_tlen]
	les	bx,[bp+10]
	mov	es:[bx],cx
	mov	ax,SUCCESS
	pop	fs
	leave
	retn
_hwRxTransfer	endp



_ServiceIntTx	proc	near
	push	offset semTx
	call	_EnterCrit
	mov	bx,[VTxInProg]
	or	bx,bx		; vtxd queue is empty
	jz	short loc_2
	mov	di,[TxCount]
	mov	al,[bx].vtxd.startpage
loc_1:
	dec	di
	jl	short loc_2
	cmp	al,[TxPageStart][di]
	jnz	short loc_1
	btr	[TxPageMask],di	; release tx page
loc_2:
	mov	dx,[IOaddr]
	mov	si,[VTxCopyHead]
	add	dx,TSR
	mov	[VTxInProg],si	; next, or zero if no copeid frame exists.
	push	offset semReg
	call	_EnterCrit
	in	al,dx
	or	si,si
	mov	cl,al
	jz	short loc_3	; no remote copied frame
	mov	di,[si].vtxd.vlink
	mov	al,[si].vtxd.startpage
	mov	[VTxCopyHead],di
;	add	dx,TPSR - TSR
	out	dx,al
	mov	ax,[si].vtxd.framelen
	inc	dx
	out	dx,al
	mov	al,ah
	inc	dx
	out	dx,al
	mov	al,STA or TXP or RD2
	add	dx,CR - TBCR1
	out	dx,al
loc_3:
	call	_LeaveCrit
	xor	ax,ax
	pop	si	; stack adjust
	or	bx,bx
	jz	short loc_6
	mov	[bx].vtxd.vlink,ax
	cmp	ax,[VTxFreeHead]
	jnz	short loc_4
	mov	[VTxFreeHead],bx
	jmp	short loc_5
loc_4:
	mov	di,[VTxFreeTail]
	mov	[di].vtxd.vlink,bx
loc_5:
	mov	[VTxFreeTail],bx
	
	mov	ax,[bx].vtxd.reqhandle
	mov	dx,[bx].vtxd.protid
loc_6:
	call	_LeaveCrit
	or	bx,bx
	pop	si	; stack ajust
	jz	short loc_7

	and	cx,PTXOK
	mov	di,[CommonChar.moduleID]
	mov	bx,[ProtDS]
	dec	cl

	push	dx	; ProtID
	push	di	; MACID
	push	ax	; ReqHandle
	push	cx	; Status
	push	bx	; ProtDS
	cld
	call	dword ptr [LowDisp.txconfirm]
loc_7:
	retn
_ServiceIntTx	endp


_ServiceIntRx	proc	near
	mov	dx,[IOaddr]
	push	bp
	push	offset semReg
	call	_EnterCrit

	mov	al,STA or RD2 or PS0
	out	dx,al		; page1
	add	dx,CURR - CR
	in	al,dx		; current page
	mov	ah,al
	add	dx,CR - CURR
	mov	al,STA or RD2
	out	dx,al	; page0
	add	dx,BNRY - CR
	in	al,dx		; boundary

	call	_LeaveCrit

	mov	[RxCurrentPage],ah
	mov	[RxBoundaryPage],al
loc_0:
	mov	al,[RxBoundaryPage]
	inc	al
	cmp	al,[RxPageStop]
	jb	short loc_1
	mov	al,[RxPageStart]
loc_1:
	cmp	al,[RxCurrentPage]
	jnz	short loc_2	; frame received
	pop	dx
	pop	bp
	mov	ax,0
	retn

loc_2:
	mov	ah,4
	add	dx,RBCR0 - BNRY
	xchg	al,ah
	mov	di,offset RxStatus
	mov	[RxRangeAddr1],ax
	push	ds
	pop	es

	call	_EnterCrit
	out	dx,al
	inc	dx
	mov	al,0
	out	dx,al		; remote byte count
	add	dx,RSAR0 - RBCR1
	out	dx,al
	mov	al,ah
	inc	dx
	out	dx,al		; remote start address
	mov	al,STA or RD0
	add	dx,CR - RSAR1
	out	dx,al		; remote read command
	add	dx,DataPort - CR
	insw
	insw
	call	_LeaveCrit

	test	[RxStatus],PRXOK
	mov	bp,[RxLength]
;	jz	short loc_9	; errored frame. next.
	jz	near ptr loc_9
	sub	bp,4		; substract CRC length
;	jna	short loc_9	; invalid length
	jna	near ptr loc_9
	mov	si,bp
	mov	ax,[RxRangeAddr1]
	cmp	bp,[cfgMAXFRAMESIZE]
;	ja	short loc_9	; too long frame. next.
	ja	near ptr loc_9
	mov	cl,0
	mov	ch,[RxPageStop]
	add	ax,si
	sub	ax,cx
	ja	short loc_3	; wraparound
	mov	[RxRangeLen1],si
	mov	[RxRangeLen2],0
	jmp	short loc_4
loc_3:
	sub	si,ax
	mov	ch,[RxPageStart]
	mov	[RxRangeLen1],si
	mov	[RxRangeLen2],ax
	mov	[RxRangeAddr2],cx
loc_4:
	mov	cx,[RxLookaheadSize]
	mov	si,bp
	cmp	bp,cx
	jb	short loc_5
	mov	si,cx
loc_5:
	mov	[RxRangeLen0],si
	mov	dx,[IOaddr]
	call	_EnterCrit
	mov	cx,[RxRangeLen1]
	cmp	si,cx
	ja	short loc_6
	mov	cx,si
loc_6:
	mov	bx,[RxRangeAddr1]
	sub	[RxRangeLen1],cx
	add	[RxRangeAddr1],cx
loc_7:
	mov	ax,cx
	sub	si,cx
	inc	ax
	add	dx,RBCR0
	and	al,-2
	out	dx,al
	mov	al,ah
	inc	dx
	out	dx,al
	mov	ax,bx
	add	dx,RSAR0 - RBCR1
	out	dx,al
	mov	al,ah
	inc	dx
	out	dx,al
	mov	al,STA or RD0
	add	dx,CR - RSAR1
	out	dx,al
	add	dx,DataPort - CR
	shr	cx,1
	rep	insw
	jnc	short loc_8
	in	ax,dx
	stosb
loc_8:
	or	si,si
	jz	short loc_9
	mov	cx,si
	mov	bx,[RxRangeAddr2]
	sub	[RxRangeLen2],cx
	add	[RxRangeAddr2],cx
	add	dx,-DataPort
	jmp	short loc_7
loc_9:
	call	_LeaveCrit

	call	_IndicationChkOFF
	or	ax,ax
	jz	short loc_10	; indicate off - discard... 

	push	-1
	mov	ax,[ProtDS]
	mov	si,sp
	mov	cx,[CommonChar.moduleID]
	mov	di,offset RxBuffer
;	mov	dx,[RxLength]
	mov	bx,[RxRangeLen0]
	
	push	cx	; MACID
	push	bp	; FrameSize
	push	bx	; ByteAvail
	push	ds
	push	di	; buffer
	push	ss
	push	si	; Indicate
	push	ax	; ProtDS
	call	dword ptr [LowDisp.rxlookahead]
	pop	ax
lock	or	[drvflags],mask df_idcp
	cmp	al,-1
	jnz	short loc_10
	call	_IndicationON
loc_10:
	mov	al,[RxNextPtr]
	mov	dx,[IOaddr]
	cmp	al,[RxPageStart]
	jnz	short loc_11
	mov	al,[RxPageStop]
loc_11:
	dec	al
	add	dx,BNRY
	mov	[RxBoundaryPage],al
	call	_EnterCrit
	out	dx,al
	call	_LeaveCrit
	jmp	near ptr loc_0
_ServiceIntRx	endp


_ServiceIntOverFlow	proc	near
	enter	2,0
	mov	dx,[IOaddr]
	push	offset semReg
	call	_EnterCrit
;	add	dx,CR
	in	al,dx
	mov	[bp-2],al
	mov	al,STP or RD2
	out	dx,al		; reset
	call	_LeaveCrit
	add	dx,ISR - CR
	mov	cx,24
loc_1:
	push	2
	call	__IODelayCnt
	pop	ax
	call	_EnterCrit
	in	al,dx		; wait reset complete
	call	_LeaveCrit
	test	al,RST
	jnz	short loc_2
	dec	cx
	jnz	loc_1
loc_2:
	mov	[bp-1],al
	call	_EnterCrit
	add	dx,RBCR0 - ISR
	mov	al,0
	out	dx,al
	inc	dx
	out	dx,al		; clear remote byte count
	add	dx,DCR - RBCR1
	mov	al,WTS or FT1
	out	dx,al		; Data Configuration loopback
	mov	al,LB0
	dec	dx
	out	dx,al		; transmit configuration loopback
	mov	al,STA or RD2
	add	dx,CR - TCR
	out	dx,al		; start loopback mode
	call	_LeaveCrit

	call	_ServiceIntRx	; rx process

	mov	dx,[IOaddr]
	call	_EnterCrit
	mov	al,OVW
	add	dx,ISR
	out	dx,al		; clear OVW status
	mov	al,WTS or LS or FT1
	add	dx,DCR - ISR
	out	dx,al		; data configuration normal mode
	mov	al,0
	dec	dx
	out	dx,al		; transmit configuraion normal mode
	test	byte ptr [bp-2],TXP	; transmit was in progress?
	jz	short loc_3
	test	byte ptr [bp-1],PTX or TXE	; transmit complete?
	jnz	short loc_3
	mov	al,STA or TXP or RD2
	add	dx,CR - TCR
	out	dx,al		; restart transmit
loc_3:
	call	_LeaveCrit
	leave
	retn
_ServiceIntOverFlow	endp


_hwServiceInt	proc	near
	enter	2,0
loc_0:
	mov	dx,[IOaddr]
	add	dx,ISR
	in	al,dx
;	cmp	al,-1
;	jz	short loc_ex
	and	al,[regIntMask]
	jz	short loc_ex
	out	dx,al
	mov	[bp-2],al

	test	byte ptr [bp-2],OVW
	jz	short loc_1
	call	_ServiceIntOverFlow
loc_1:
	test	byte ptr [bp-2],PTX or TXE
	jz	short loc_2
	call	_ServiceIntTx
loc_2:
	test	byte ptr [bp-2],PRX or RXE
	jz	short loc_3
	call	_ServiceIntRx
loc_3:
	test	byte ptr [bp-2],CNT
	jz	short loc_4
	call	_hwUpdateStat
loc_4:
	test	byte ptr [bp-2],PTX or TXE
	jz	short loc_5
loc_41:
	call	_TxRemoteDMA
	test	ax,ax
	jnz	short loc_41
loc_5:
	jmp	short loc_0

loc_ex:
	leave
	retn
_hwServiceInt	endp

_hwCheckInt	proc	near
	mov	dx,[IOaddr]
	push	offset semReg
	call	_EnterCrit
	add	dx,ISR
	in	al,dx
	call	_LeaveCrit
	test	al,[regIntMask]
	pop	dx
	setnz	al
	mov	ah,0
	retn
_hwCheckInt	endp

_hwEnableInt	proc	near
	mov	dx,[IOaddr]
	push	offset semReg
	call	_EnterCrit
	mov	al,[regIntMask]
	add	dx,IMR
	out	dx,al
	call	_LeaveCrit
	pop	ax
	retn
_hwEnableInt	endp

_hwDisableInt	proc	near
	mov	dx,[IOaddr]
	mov	al,0
	add	dx,IMR
	push	offset semReg
	call	_EnterCrit
	out	dx,al
	call	_LeaveCrit
	pop	ax
	retn
_hwDisableInt	endp

_hwIntReq	proc	near
	push	offset semTx
	call	_EnterCrit
	cmp	[VTxInProg],0
	jnz	short loc_1

	mov	dx,[IOaddr]
	push	offset semReg
	call	_EnterCrit
	mov	al,0
	add	dx,TBCR0
	out	dx,al
	inc	dx
	out	dx,al
	mov	al,STA or TXP or RD2
	add	dx,CR - TBCR1
	out	dx,al
	call	_LeaveCrit
	pop	ax
loc_1:
	call	_LeaveCrit
	pop	ax

	retn
_hwIntReq	endp

_hwEnableRxInd	proc	near
lock	or	[regIntMask],PRX or RXE or OVW
	cmp	[semInt],0
	jnz	short loc_1

	push	ax
	push	dx
	push	offset semReg
	call	_EnterCrit
	mov	dx,[IOaddr]
	mov	al,[regIntMask]
	add	dx,IMR
	out	dx,al
	call	_LeaveCrit
	pop	ax
	pop	dx
	pop	ax
loc_1:
	retn
_hwEnableRxInd	endp

_hwDisableRxInd	proc	near
lock	and	[regIntMask],not(PRX or RXE or OVW)
	cmp	[semInt],0
	jnz	short loc_1

	push	ax
	push	dx
	push	offset semReg
	call	_EnterCrit
	mov	dx,[IOaddr]
	mov	al,[regIntMask]
	add	dx,IMR
	out	dx,al
	call	_LeaveCrit
	pop	ax
	pop	dx
	pop	ax
loc_1:
	retn
_hwDisableRxInd	endp

_hwPollLink	proc	near
	retn			; do nothing
_hwPollLink	endp

_hwOpen		proc	near	; call in protocol bind process?

	call	_SetMacEnv
	call	_hwUpdatePktFlt		; clear/update RxCR
	call	_hwUpdateMulticast	; clear/update MARx

	mov	dx,[IOaddr]
	push	offset semReg
	call	_EnterCrit
	mov	al,WTS or LS or FT1	; leave loopback mode
	add	dx,DCR
	out	dx,al
	mov	al,0
;	add	dx,TCR - DCR
	dec	dx
	out	dx,al

	mov	[regIntStatus],al
	add	dx,ISR - TCR
	mov	al,-1			; clear interrupt status
	out	dx,al
	mov	al,PRX or PTX or RXE or TXE or OVW or CNT
	add	dx,IMR - ISR
	mov	[regIntMask],al
	out	dx,al			; enable interrupt
	call	_LeaveCrit
	pop	dx	; stack adjust

	mov	ax,SUCCESS
loc_e:
	retn
_hwOpen		endp

_SetMacEnv	proc	near
	mov	al,[RxPageStart]
	mov	ah,[RxPageStop]
	dec	ah
	mov	[RxCurrentPage],al
	mov	[RxBoundaryPage],ah

	mov	dx,[IOaddr]
	push	offset semReg
	call	_EnterCrit
	mov	al,[RxPageStart]
;	add	dx,PSTART
	inc	dx
	out	dx,al
	mov	al,[RxPageStop]
;	add	dx,PSTOP - PSTART
	inc	dx
	out	dx,al
	mov	al,[RxBoundaryPage]
;	add	dx,BNRY - PSTOP
	inc	dx
	out	dx,al
	mov	al,STA or RD2 or PS0
	add	dx,CR - BNRY
	out	dx,al
	mov	al,[RxCurrentPage]
	add	dx,CURR - CR
	out	dx,al
	mov	al,STA or RD2
	add	dx,CR - CURR
	out	dx,al
	call	_LeaveCrit
	pop	ax

	retn
_SetMacEnv	endp


_hwUpdateMulticast	proc	near
	enter	2,0
	push	si
	push	di
	push	offset semFlt
	call	_EnterCrit
	mov	di,offset regHashTable
	push	ds
	pop	es
	xor	eax,eax
	test	[regReceiveMode],PRO
	jnz	short loc_2
	stosd			; clear hash table
	stosd

	mov	ax,[MCSTList.curnum]
	mov	[bp-2],ax
loc_1:
	dec	word ptr [bp-2]
	jl	short loc_3
	mov	ax,[bp-2]
	shl	ax,4		; 16bytes
	add	ax,offset MCSTList.multicastaddr1
	push	ax
	call	_CRC32
	shr	eax,26		; the 6 most significant bits
	mov	di,ax
	pop	cx
	shr	di,4
	and	ax,0fh		; the bit index in word
	add	di,di		; the word index (2byte)
	bts	word ptr regHashTable[di],ax
	jmp	short loc_1

loc_2:
	dec	eax		; accept all multicast
	stosd
	stosd
loc_3:
	mov	dx,[IOaddr]
	mov	si,offset regHashTable
	mov	cx,8

	push	offset semReg
	call	_EnterCrit
	mov	al,STA or RD2 or PS0
	out	dx,al
	add	dx,MAR0 - CR
loc_4:
	lodsb
	out	dx,al
	inc	dx
	dec	cx
	jnz	short loc_4
	mov	al,STA or RD2
	add	dx,CR - MAR7 -1
	out	dx,al

	call	_LeaveCrit
	pop	ax
	call	_LeaveCrit
	pop	cx

	mov	ax,SUCCESS
	pop	di
	pop	si
	leave
	retn
_hwUpdateMulticast	endp

_CRC32		proc	near
POLYNOMIAL_be	equ	 04C11DB7h
POLYNOMIAL_le	equ	0EDB88320h

	push	bp
	mov	bp,sp
	mov	ch,3
	mov	bx,[bp+4]
	or	eax,-1
loc_1:
	mov	bp,[bx]
	mov	cl,10h
	inc	bx
loc_2:
IF 1
		; big endian
	shl	eax,1
	rcl	dx,1
	xor	dx,bp
	shr	dx,1
	sbb	edx,edx
	and	edx,POLYNOMIAL_be
ELSE
		; little endian
	shr	eax,1
	rcl	dx,1
	xor	dx,bp
	shr	dx,1
	sbb	edx,edx
	and	edx,POLYNOMIAL_le
ENDIF
	xor	eax,edx
	shr	bp,1
	dec	cl
	jnz	short loc_2
	inc	bx
	dec	ch
	jnz	short loc_1
	pop	bp
	retn
_CRC32		endp


_hwUpdatePktFlt	proc	near
	mov	dx,[IOaddr]
	xor	ax,ax
	add	dx,RxCR

	push	offset semFlt
	call	_EnterCrit

	mov	cx,[MacStatus.sstRxFilter]

	test	cl,mask fltdirect
	jz	short loc_1
	or	al,AM			; multicast
loc_1:
	test	cl,mask fltbroad
	jz	short loc_2
	or	al,AB			; broadcast
loc_2:
	test	cl,mask fltprms
	jz	short loc_3
	or	al,PRO or AB or AM	; promiscous
loc_3:
	push	offset semReg
	call	_EnterCrit
	mov	[regReceiveMode],al
	out	dx,al
	call	_LeaveCrit
	pop	cx
	call	_LeaveCrit
	pop	cx

	test	al,PRO
	jz	short loc_4
	call	_hwUpdateMulticast	; all multicast
loc_4:
	mov	ax,SUCCESS
	retn
_hwUpdatePktFlt	endp

_hwSetMACaddr	proc	near
	push	si
	push	offset semFlt
	call	_EnterCrit
	mov	si,offset MacChar.mctcsa
	mov	ax,[si]
	or	ax,[si+2]
	or	ax,[si+4]
	jnz	short loc_1
	mov	si,offset MacChar.mctpsa
loc_1:
	mov	cx,6
	mov	dx,[IOaddr]
	push	offset semReg
	call	_EnterCrit
	mov	al,STA or RD2 or PS0	; page1
	out	dx,al
loc_2:
	inc	dx
	dec	cx
	lodsb
	out	dx,al
	jnz	short loc_2
	mov	al,STA or RD2		; page0
	add	dx,CR - PAR5
	out	dx,al

	call	_LeaveCrit
	pop	ax
	call	_LeaveCrit
	pop	cx
	mov	ax,SUCCESS
	pop	si
	retn
_hwSetMACaddr	endp

_hwSetLookahead	proc	near
	push	bp
	mov	bp,sp
	mov	ax,[bp+4]
	cmp	ax,64
	jc	short loc_2
	cmp	ax,256
	ja	short loc_2
	cmp	ax,[RxLookaheadSize]
	jc	short loc_1
	inc	ax
	and	al,-2
	mov	[RxLookaheadSize],ax
loc_1:
	pop	bp
	mov	ax,SUCCESS
	retn
loc_2:
	pop	bp
	mov	ax,INVALID_PARAMETER
	retn
_hwSetLookahead	endp

_hwUpdateStat	proc	near
	push	offset semStat
	call	_EnterCrit
	push	offset semReg
	call	_EnterCrit

	mov	dx,[IOaddr]
	mov	bx,offset MacStatus
	xor	eax,eax
	add	dx,CNTR0	; frame alignment error
	in	al,dx
	add	[bx].mst.rxframecrc,eax

	inc	dx		; CRC error
	in	al,dx
	add	[bx].mst.rxframecrc,eax

	inc	dx
	in	al,dx		; missed packet
	add	[bx].mst.rxframehw,eax

	add	dx,NCR - CNTR2
	in	al,dx
	add	[bx].mst.txframeto,eax

	call	_LeaveCrit
	pop	ax
	call	_LeaveCrit
	pop	ax
	retn
_hwUpdateStat	endp

_hwClearStat	proc	near
	mov	dx,[IOaddr]
	push	offset semReg
	call	_EnterCrit
	add	dx,NCR
	in	al,dx
	add	dx,CNTR0 - NCR
	in	al,dx
	inc	dx
	in	al,dx
	inc	dx
	in	al,dx
	call	_LeaveCrit
	pop	ax
	retn
_hwClearStat	endp


_hwClose	proc	near
	push	offset semTx
	call	_EnterCrit
	push	offset semReg
	call	_EnterCrit

	mov	dx,[IOaddr]
	mov	al,0
	add	dx,IMR
	out	dx,al		; clear interrupt mask register
	mov	[regIntMask],al

	add	dx,CR - IMR
	mov	al,STP or RD2	; stop(reset)
	out	dx,al
	add	dx,ISR - CR
	mov	cx,9
	push	4
loc_1:
	call	__IODelayCnt
	in	al,dx
	test	al,RST
	loopz	short loc_1	; reset or timeout?
	pop	cx	; stack adjust

	mov	al,LB0		; enter loopback mode
	add	dx,TCR - ISR
	out	dx,al
	mov	al,WTS or FT1
;	add	dx,DCR - TCR
	inc	dx
	out	dx,al
	mov	al,STA or RD2
	add	dx,CR - DCR
	out	dx,al

	call	_LeaveCrit
	pop	dx
	call	_LeaveCrit
	pop	dx

	mov	ax,SUCCESS
	retn
_hwClose	endp

_hwReset	proc	near	; call in bind process
	enter	6,0

	mov	dx,[IOaddr]
	push	offset semReg
	call	_EnterCrit

	add	dx,Unknown
	in	al,dx
	mov	al,-1
	out	dx,al		; read and write -1. Functionality unknown.
	
	mov	al,STP or RD2
	add	dx,CR - Unknown
	out	dx,al		; reset status
	in	al,dx
	and	al,0fdh
	cmp	al,STP or RD2	; hardware present?
;	jnz	short loc_e
	jnz	near ptr loc_e

loc_0:
	mov	al,LB0		; NIC loopback mode
	add	dx,TCR - CR
	out	dx,al
	mov	al,WTS or FT1	; loopback
	add	dx,DCR - TCR
	out	dx,al
	mov	al,STA or RD2
	add	dx,CR - DCR
	out	dx,al		; start in loopback mode

	mov	al,0		; internal memory test
	add	dx,RBCR0 - CR
	out	dx,al
	mov	al,40h		; length 4000h
	inc	dx
	out	dx,al
	mov	al,0
	add	dx,RSAR0 - RBCR1
	out	dx,al
	mov	al,40h		; start page 40h
	inc	dx
	out	dx,al
	mov	al,STA or RD1	; remote write command
	add	dx,CR - RSAR1
	out	dx,al
	mov	cx,4000h/2
	mov	ax,0e5e5h
	add	dx,DataPort - CR
loc_1:
	dec	cx
	out	dx,ax		; fill 0e5h 
	jnz	short loc_1

	mov	cx,offset DosIODelayCnt
	add	dx,CR - DataPort
loc_2:
	in	al,dx
	test	al,RD2		; remote command compete?
	jnz	short loc_3
	jmp	short $+2
	jmp	short $+2
	loop	short loc_2
	jmp	short loc_e	; timeout
loc_3:
	mov	al,0
	add	dx,RBCR0 - CR
	out	dx,al
	mov	al,40h		; length
	inc	dx
	out	dx,al
	mov	al,0
	add	dx,RSAR0 - RBCR1
	out	dx,al
	mov	al,40h		; start address
	inc	dx
	out	dx,al
	mov	al,STA or RD0	; remote read command
	add	dx,CR - RSAR1
	out	dx,al
	mov	cx,4000h/2
	add	dx,DataPort - CR
loc_4:
	in	ax,dx
	cmp	ax,0e5e5h	; test 0e5h
	jnz	short loc_e
	dec	cx
	jnz	short loc_4
	add	dx,CR - DataPort
	mov	cx,offset DosIODelayCnt
loc_5:
	in	al,dx
	test	al,RD2		; remote command complete?
	jnz	short loc_6
	jmp	short $+2
	jmp	short $+2
	loop	short loc_5
;	jmp	short loc_e	; timeout

loc_e:
	call	_LeaveCrit
	mov	ax,HARDWARE_FAILURE
	leave
	retn

loc_6:
	mov	al,0		; read physical address from PROM
	add	dx,RBCR0 - CR
	out	dx,al
	mov	al,6*2
	inc	dx
	out	dx,al
	mov	al,0
	add	dx,RSAR0 - RBCR1
	out	dx,al
	inc	dx
	out	dx,al
	mov	al,STA or RD0
	add	dx,CR - RSAR1
	out	dx,al
	add	dx,DataPort - CR
	mov	di,-6
loc_7:
	in	ax,dx
	mov	[bp+di],al
	inc	di
	jnz	short loc_7

	call	_LeaveCrit

	push	offset semFlt
	call	_EnterCrit
	mov	ax,[bp-6]
	mov	cx,[bp-4]
	mov	dx,[bp-2]
	mov	word ptr MacChar.mctpsa,ax	; parmanent
	mov	word ptr MacChar.mctpsa[2],cx
	mov	word ptr MacChar.mctpsa[4],dx
	mov	word ptr MacChar.mctcsa,ax	; current
	mov	word ptr MacChar.mctcsa[2],cx
	mov	word ptr MacChar.mctcsa[4],dx
	mov	word ptr MacChar.mctVendorCode,ax ; vendor
	mov	byte ptr MacChar.mctVendorCode,cl
	call	_LeaveCrit
	add	sp,2*2
	call	_hwSetMACaddr		; update PARx
	mov	ax,SUCCESS
	leave
	retn
_hwReset	endp


; void _IODelayCnt( USHORT count )
__IODelayCnt	proc	near
	push	bp
	mov	bp,sp
	push	cx
	mov	bp,[bp+4]
loc_1:
	mov	cx,offset DosIODelayCnt
	dec	bp
	loop	$
	jnz	short loc_1
	pop	cx
	pop	bp
	retn
__IODelayCnt	endp


_TEXT	ends
end
