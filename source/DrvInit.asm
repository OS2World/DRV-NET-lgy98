; *** Initial part

include	NDISdef.inc
include	lgy98.inc
include	devpac.inc
include	OEMHelp.inc
include	DrvRes.inc
include	HWRes.inc

cfgKeyDesc	struc
NextKey		dw	?
KeyStrPtr	dw	?
KeyStrLen	dw	?
KeyProc		dw	?
cfgKeyDesc	ends

cwRCRD		record  cwRsv:13 = 0,
		cwVTXQ:1 = 0,
		cwTXQ:1 = 0,
		cwUnk:1 = 0

cr	equ	0dh
lf	equ	0ah

extern	Dos16Open : far16
extern	Dos16Close : far16
extern	Dos16DevIOCtl : far16
extern	Dos16PutMessage : far16

.386

_DATA	segment	public word use16 'DATA'

DS_Lin		dd	?
HeapEnd		dw	offset HeapStart
HeapStart:

handle_Protman	dw	?
name_Protman	db	'PROTMAN$',0
TmpDrvName	db	'LGY98$',0,0


PMparm		PMBlock	<>

DrvKeyword1	cfgKeyDesc  < offset DrvKeyword2, offset strKeyword1, \
		 lenKeyword1, offset sci_IOBASE >
DrvKeyword2	cfgKeyDesc  < offset DrvKeyword3, offset strKeyword2, \
		 lenKeyword2, offset sci_INTERRUPT >
DrvKeyword3	cfgKeyDesc  < offset DrvKeyword4, offset strKeyword3, \
		 lenKeyword3, offset sci_TXQUEUE >
DrvKeyword4	cfgKeyDesc  < 0, offset strKeyword4, \
		 lenKeyword4, offset sci_LTXQUEUE >


cfgKeyWarn	cwRCRD	<>


Key_DRIVERNAME	db	'DRIVERNAME',0,0
strKeyword1	db	'IOBASE',0
lenKeyword1	equ	$ - offset strKeyword1
strKeyword2	db	'INTERRUPT',0
lenKeyword2	equ	$ - offset strKeyword2
strKeyword3	db	'TXQUEUE',0
lenKeyword3	equ	$ - offset strKeyword3
strKeyword4	db	'LTXQUEUE',0
lenKeyword4	equ	$ - offset strKeyword4



msg_OSEnvFail	db	'?! Invalid System Information?!',cr,lf,0
msg_ManyInst	db	'Too many module was installed.',cr,lf,0
msg_NoProtman	db	'Protocol manager open failure.',cr,lf,0
msg_ProtIOCtl	db	'Protocol manager IOCtl failure.',cr,lf,0
msg_ProtLevel	db	'Invalid protocol manager level.',cr,lf,0
msg_NoModule	db	'Module not found in PROTOCOL.INI',cr,lf,0

msg_InvIOaddr	db	'IOBASE keyword specifies invalid I/O address range.',cr,lf,0
msg_InvIRQlevel	db	'INTERRUPT keyword specifies invalid IRQ Level.',cr,lf,0

; msg_CtxFail	db	'Context Hook handle allocation failure.',cr,lf,0
msg_NoSel	db	'GDT Selector to copy Tx/Rx buffer allocation failure.',cr,lf,0
msg_RegFail	db	'Module registration to protocol manager failure.',cr,lf,0
Credit		db	cr,lf,' MELCO LGY-98 OS/2 NDIS MAC Driver '
		db	'ver.1.00. (2003-06-18)',cr,lf,0
Copyright	db	0	; Write copyright message here if you want.

Heap		db	( 8*sizeof(vtxd) ) dup (0)

_DATA	ends

_TEXT	segment	public word use16 'CODE'
	assume	ds:_DATA

public	Strategy
Strategy	proc	far
;	int	3		; << debug >>
	mov	al,es:[bx]._RPH.Cmd
	cmp	al,CMDOpen
	jz	short loc_OC
	cmp	al,CMDClose
	jnz	short loc_1
loc_OC:
	mov	es:[bx]._RPH.Status,100h
	retf
loc_E:
	mov	es:[bx]._RPH.Status,8103h
	retf
loc_1:
	cmp	al,CMDInit
	jnz	short loc_E
	push	es
	push	bx
	call	_DrvInit
	pop	bx
	pop	es
	retf
Strategy	endp

_DrvInit		proc	near
	enter	2,0		; -2:error message offset
	les	bx,[bp+4]
	mov	eax,es:[bx]._RPINIT.DevHlpEP
	mov	[DevHelp],eax

	push	offset Credit
	call	_PutMessage
	push	offset Copyright
	call	_PutMessage
	add	sp,2+2

	call	_SetDrvEnv
	or	ax,ax
	jnz	short loc_rnm
	mov	[bp-2],offset msg_OSEnvFail
	jmp	short loc_err1

loc_rnm:
	call	_ResolveName
	or	ax,ax
	jnz	short loc_protop
	mov	[bp-2],offset msg_ManyInst
	jmp	short loc_err1

loc_protop:
	call	_OpenProtman
	or	ax,ax
	jnz	short loc_protcfg
	mov	[bp-2],offset msg_NoProtman
	jmp	short loc_err1

loc_protcfg:
	call	_ScanConfigImage
	or	ax,ax
	jnz	short loc_agdt
	mov	[bp-2],dx
	jmp	short loc_err2

loc_agdt:
	call	_AllocGDT
	or	ax,ax
	jnz	short loc_ctx
	mov	[bp-2],offset msg_NoSel
	jmp	short loc_err2

loc_ctx:
;	call	_AllocCtxHook
;	or	ax,ax
;	jnz	short loc_protreg
;	mov	[bp-2],offset msg_CtxFail
;	jmp	short loc_err3

loc_protreg:
	call	_RegisterModule
	or	ax,ax
	jnz	short loc_OK
	mov	[bp-2],offset msg_RegFail
	jmp	short loc_err4

loc_OK:
	call	_CloseProtman
	call	_InitQueue
	les	bx,[bp+4]
	mov	ax,[HeapEnd]
	mov	es:[bx]._RPINITOUT.CodeEnd,offset _DrvInit
	mov	es:[bx]._RPINITOUT.DataEnd,ax
	mov	es:[bx]._RPH.Status,100h
	leave
	retn

loc_err4:
loc_err3:
	call	_ReleaseGDT
loc_err2:
	call	_CloseProtman
loc_err1:
	push	word ptr [bp-2]
	call	_PutMessage
;	pop	ax
	les	bx,[bp+4]
	mov	es:[bx]._RPINITOUT.CodeEnd,0
	mov	es:[bx]._RPINITOUT.DataEnd,0
	mov	es:[bx]._RPH.Status,8115h	; quiet init fail
	leave
	retn
	
_DrvInit	endp


_ResolveName	proc	near
	enter	6,0
	push	si
	push	di
	xor	bx,bx
	mov	si,offset TmpDrvName
loc_1:
	cmp	byte ptr [bx+si],'$'
	jz	short loc_2
	inc	bx
	cmp	bx,8
	jb	short loc_1
loc_e:
	xor	ax,ax		; invalid name
	jmp	near ptr loc_err
loc_2:
	test	bx,bx
	jz	short loc_e
	mov	[bp-2],bx
	mov	byte ptr [bx+si+1],0
loc_3:
	lea	di,[bp-4]
	lea	bx,[bp-6]
	push	ds
	push	si		; name
	push	ss
	push	bx		; handle
	push	ss
	push	di		; action
	push	0
	push	0		; file size
	push	0		; attribute
	push	1		; Open flag
	push	42h		; Open mode
	push	0		; reserve
	push	0
	call	Dos16Open
	or	ax,ax
	jnz	short loc_5	; this name is not used. OK.

	push	word ptr [bp-6]
	call	Dos16Close
	mov	bx,[bp-2]
	cmp	bx,7		; already max length
	jnb	short loc_e
	mov	si,offset TmpDrvName
	cmp	byte ptr [bx+si],'$'
	jz	short loc_4	; first modification
	cmp	byte ptr [bx+si],'9'
	jz	short loc_e	; last modification. failure.
	inc	byte ptr [bx+si]
	jmp	short loc_3
loc_4:
	mov	word ptr [bx+si],'$1'
	mov	byte ptr [bx+si+2],0
	jmp	short loc_3

loc_5:
	mov	cx,8
	mov	si,offset TmpDrvName
	mov	di,offset DrvName
	push	ds
	pop	es
	cld
loc_6:
	lodsb
	cmp	al,0
	jz	short loc_7
	stosb
	dec	cx
	jnz	short loc_6
loc_7:
	jcxz	short loc_8
	mov	al,' '
	rep	stosb

loc_8:
	mov	ax,1
loc_err:
	pop	di
	pop	si
	leave
	retn
_ResolveName	endp


_OpenProtman	proc	near
	enter	2,0
	mov	ax,sp
	push	ds
	push	offset name_Protman	; file name
	push	ds
	push	offset handle_Protman	; file handle
	push	ss
	push	ax		; action taken
	push	0
	push	0		; File size
	push	0		; File attribute
	push	1		; Open flag (Open if exist)
	push	42h		; Open Mode
	push	0
	push	0		; reserve (NULL)
	call	Dos16Open
	mov	dx,ax
	neg	ax
	sbb	ax,ax
	inc	ax
	leave
	retn
_OpenProtman	endp

_CloseProtman	proc	near
	mov	ax,[handle_Protman]
	push	ax
	call	Dos16Close
	retn
_CloseProtman	endp

_RegisterModule	proc	near
	mov	cx,cs
	mov	ax,ds
	and	cl,-8

	mov	CommonChar.moduleDS,ax
	mov	word ptr CommonChar.cctsrd[2],cx
	mov	word ptr CommonChar.cctssc[2],ax
	mov	word ptr CommonChar.cctsss[2],ax
	mov	word ptr CommonChar.cctupd[2],ax
	mov	word ptr MacChar.mcal[2],ax
	mov	word ptr MacChar.mctAdapterDesc[2],ax
	mov	word ptr UpDisp.updpbp[2],ax
	mov	word ptr UpDisp.request[2],cx
	mov	word ptr UpDisp.txchain[2],cx
	mov	word ptr UpDisp.rxdata[2],cx
	mov	word ptr UpDisp.rxrelease[2],cx
	mov	word ptr UpDisp.indon[2],cx
	mov	word ptr UpDisp.indoff[2],cx

	mov	al,IRQlevel
	mov	ah,0
	mov	MacChar.mctIRQ,ax
	mov	al,cfgVTXQUEUE
	mov	dx,cfgMAXFRAMESIZE
	mov	MacChar.mcttqd,ax
	mov	MacChar.mfs,dx
	mov	MacChar.tbs,dx
	mov	MacChar.rbs,dx
	mul	dx
	mov	word ptr MacChar.ttbc,ax
	mov	word ptr MacChar.ttbc[2],dx
	mov	al,cfgRXQUEUE
	mov	ah,0
	mov	dx,1536		; rx fragment size
	mul	dx
	mov	word ptr MacChar.trbc,ax
	mov	word ptr MacChar.trbc[2],dx
	mov	MacChar.linkspeed,10000000

	xor	ax,ax
	mov	PMparm.PMCode,RegisterModule	; opcode 2
	mov	word ptr PMparm.PMPtr1,offset CommonChar
	mov	word ptr PMparm.PMPtr1[2],ds
	mov	word ptr PMparm.PMPtr2,ax
	mov	word ptr PMparm.PMPtr2[2],ax
	mov	PMparm.PMWord,ax

	push	ax
	push	ax
	push	ds
	push	offset PMparm
	push	ProtManCode
	push	LanManCat
	push	[handle_Protman]
	call	Dos16DevIOCtl

	neg	ax
	sbb	ax,ax
	inc	ax
	retn
_RegisterModule	endp


_ScanConfigImage	proc	near
	mov	[PMparm.PMCode],GetProtManInfo	; opcode 1
	push	0
	push	0		; data (NULL)
	push	ds
	push	offset PMparm	; parameter
	push	ProtManCode	; function 58h
	push	LanManCat	; category 81h
	push	word ptr [handle_Protman]
	call	Dos16DevIOCtl
	or	ax,ax
	mov	dx,offset msg_ProtIOCtl
	jnz	short loc_e1
	cmp	[PMparm.PMWord],ProtManLevel	; level 1
	jz	short loc_0
	mov	dx,offset msg_ProtLevel
loc_e1:
	push	dx
	call	_PutMessage
	pop	dx
	xor	ax,ax
	retn


loc_0:
	push	bp
	push	si
	push	di
	push	gs
	cld
			; --- scan driver name ---
			; es:bx = module,  es:bp = keyword
	lgs	bx,[PMparm.PMPtr1]
loc_Module:
	mov	ax,gs
	mov	es,ax
	lea	bp,[bx].ModuleConfig.Keyword1

loc_NameKey:
	mov	si,offset Key_DRIVERNAME	; 'DRIVERNAME'
	mov	cx,12/4
	lea	di,[bp].KeywordEntry.Keyword
	repz	cmpsd
	jnz	short loc_NextNameKey
	lea	di,[bp].KeywordEntry.cmiParam1
	cmp	es:[di].cmiParam.ParamType,1	; type is string?
	jnz	short loc_NextModule
	mov	cx,es:[di].cmiParam.ParamLen
	mov	si,offset TmpDrvName
	lea	di,[di].cmiParam.Param
	repz	cmpsb
	jz	short loc_found_drv

loc_NextModule:
	cmp	gs:[bx].ModuleConfig.NextModule,0
	jz	short loc_NoModule
	lgs	bx,gs:[bx].ModuleConfig.NextModule
	jmp	short loc_Module

loc_NextNameKey:
	cmp	es:[bp].KeywordEntry.NextKeyword,0
	jz	short loc_NextModule
	les	bp,es:[bp].KeywordEntry.NextKeyword
	jmp	short loc_NameKey


loc_found_drv:
	mov	di,offset CommonChar.cctname
	lea	si,[bx].ModuleConfig.ModuleName
	mov	cx,16/4
	push	es
	push	ds
	pop	es
			; set ModuleName in common char. table
	rep	movsd	es:[di],gs:[si]
	pop	es

loc_KeyM:
	cmp	es:[bp].KeywordEntry.NextKeyword,0
	jz	short loc_KeyEnd
	les	bp,es:[bp].KeywordEntry.NextKeyword

	mov	bx,offset DrvKeyword1
loc_KeyD:
	lea	di,[bp].KeywordEntry.Keyword
	mov	si,[bx].cfgKeyDesc.KeyStrPtr
	mov	cx,[bx].cfgKeyDesc.KeyStrLen
	repz	cmpsb
	jnz	short loc_KeyD1
	call	word ptr [bx].cfgKeyDesc.KeyProc
	jnc	short loc_KeyM
	jmp	short loc_BadKey

loc_KeyD1:
	mov	bx,[bx].cfgKeyDesc.NextKey
	or	bx,bx
	jnz	short loc_KeyD
	jmp	short loc_UnknownKey

loc_UnknownKey:
	or	cfgKeyWarn,mask cwUnk	; Warning: Unknown
	jmp	short loc_KeyM

loc_NoModule:
	mov	dx,offset msg_NoModule
loc_BadKey:
;	push	dx
;	call	_PutMessage
;	add	sp,2
	xor	ax,ax
	jmp	short loc_scmExit

loc_KeyEnd:
	mov	ax,1
loc_scmExit:
	pop	gs
	pop	di
	pop	si
	pop	bp
	retn

; --- Keyword check ---  es:bp = KeywordEntry
sci_IOBASE	proc	near
	cmp	es:[bp].KeywordEntry.NumParams,1
	jnz	short loc_ce
	cmp	es:[bp].KeywordEntry.cmiParam1.ParamType,0
	jnz	short loc_ce
	mov	ax,word ptr es:[bp].KeywordEntry.cmiParam1.Param
	cmp	al,0d0h
	jnz	short loc_ce
	cmp	ah,8
	jnc	short loc_ce
	
	mov	[cfgIOBASE],ax
	mov	[IOaddr],ax
	clc
	ret
loc_ce:
	mov	dx,offset msg_InvIOaddr
	stc
	retn
sci_IOBASE	endp

sci_INTERRUPT	proc	near
	cmp	es:[bp].KeywordEntry.NumParams,1
	jnz	short loc_ce
	cmp	es:[bp].KeywordEntry.cmiParam1.ParamType,0
	jnz	short loc_ce
	mov	al,byte ptr es:[bp].KeywordEntry.cmiParam1.Param
	cmp	al,6
	jb	short loc_b
	jz	short loc_0
	cmp	al,12
	jz	short loc_0
	jmp	short loc_ce
loc_b:
	cmp	al,3
	jz	short loc_0
	cmp	al,5
	jnz	short loc_ce
loc_0:	
	mov	[cfgIRQLevel],al
	mov	[IRQlevel],al
	clc
	retn
loc_ce:
	mov	dx,offset msg_InvIRQlevel
	stc
	retn
sci_INTERRUPT	endp

sci_TXQUEUE	proc	near
	cmp	es:[bp].KeywordEntry.NumParams,1
	jnz	short loc_ce
	cmp	es:[bp].KeywordEntry.cmiParam1.ParamType,0
	jnz	short loc_ce
	mov	al,byte ptr es:[bp].KeywordEntry.cmiParam1.Param
	mov	ah,10
	cmp	al,1
	jb	short loc_w
	cmp	al,4
	ja	short loc_w
	sub	ah,al
	mov	cfgTXQUEUE,al
	mov	cfgRXQUEUE,ah
loc_ex:
	clc
	retn
loc_w:
loc_ce:
	or	cfgKeyWarn,mask cwTXQ	; Warning: out of range.
	jmp	short loc_ex
sci_TXQUEUE	endp

sci_LTXQUEUE	proc	near
	cmp	es:[bp].KeywordEntry.NumParams,1
	jnz	short loc_ce
	cmp	es:[bp].KeywordEntry.cmiParam1.ParamType,0
	jnz	short loc_ce
	mov	al,byte ptr es:[bp].KeywordEntry.cmiParam1.Param
	mov	ah,2
	cmp	al,ah
	jb	short loc_w
	mov	ah,8
	cmp	al,ah
	ja	short loc_w
	mov	cfgVTXQUEUE,al
loc_ex:
	clc
	retn
loc_w:
	mov	al,ah
loc_ce:
	or	cfgKeyWarn,mask cwVTXQ	; Warning: out of range.
	jmp	short loc_ex
sci_LTXQUEUE	endp

_ScanConfigImage	endp



_AllocGDT	proc	near
	enter	4,0
	push	di
	push	es
	push	ss
	pop	es
	lea	di,[bp-4]
	mov	cx,2
	mov	dl,DevHlp_AllocGDTSelector
	call	dword ptr [DevHelp]
	jc	short loc_err
	mov	ax,[bp-4]
	mov	cx,[bp-2]
	mov	[TxCopySel],ax
	mov	[RxCopySel],cx
loc_err:
	setnc	al
	mov	ah,0
	pop	es
	pop	di
	leave
	retn
_AllocGDT	endp

_ReleaseGDT	proc	near
	mov	ax,[TxCopySel]
	mov	dl,DevHlp_FreeGDTSelector
	call	dword ptr [DevHelp]
	mov	ax,[RxCopySel]
	mov	dl,DevHlp_FreeGDTSelector
	call	dword ptr [DevHelp]
	retn
_ReleaseGDT	endp


_InitQueue	proc	near
	enter	2,0
	mov	bl,[cfgTXQUEUE]
	mov	bh,0
	mov	[TxCount],bx
	mov	al,40h
loc_1:
	mov	[TxPageStart][bx-1],al
	add	al,6
	dec	bx
	jnz	short loc_1

	mov	[RxPageStart],al
	mov	[RxPageStop],80h
	mov	al,[cfgVTXQUEUE]
	xchg	ax,bx
	mov	[bp-2],bl
	
	mov	[TxPageMask],ax
	mov	[VTxFreeHead],ax
	mov	[VTxHead],ax
	mov	[VTxCopyHead],ax
	mov	[VTxInProg],ax

	push	0
	push	sizeof(vtxd)
loc_2:
	call	_AllocHeap
	cmp	[VTxFreeHead],0
	jnz	short loc_3
	mov	[VTxFreeHead],ax
	jmp	short loc_4
loc_3:
	mov	bx,[VTxFreeTail]
	mov	[bx].vtxd.vlink,ax
loc_4:
	mov	[VTxFreeTail],ax
	dec	byte ptr [bp-2]
	jnz	short loc_2

	leave
	mov	ax,1
	retn

; pheap AllocHeap( ushort size, ushort align);
_AllocHeap	proc	near
	push	bp
	mov	bp,sp
	push	cx
	push	dx
	mov	cx,[bp+4]	; size
	mov	bp,[bp+6]	; alignment
	bsf	ax,bp
	jz	short loc_ok	; no alignment
	bsr	dx,bp
	sub	ax,dx
	jnz	short loc_e	; alignment error
	cmp	cx,4096
	ja	short loc_e	; > page size
	mov	ax,[HeapEnd]
	mov	dx,bp
	add	ax,word ptr [DS_Lin]
	dec	dx
	and	ax,dx
	jz	short loc_1	; alignment ok
	sub	ax,bp
	sub	[HeapEnd],ax	; alignment adjust
loc_1:
	mov	ax,[HeapEnd]
	mov	dx,cx
	add	ax,word ptr [DS_Lin]
	dec	dx
	mov	bp,ax
	add	ax,dx
	xor	ax,bp
	test	ax,-1000h	; in a page
	jz	short loc_ok
	and	bp,0fffh
	sub	bp,1000h
	sub	[HeapEnd],bp	; page top
loc_ok:
	mov	ax,[HeapEnd]
	add	[HeapEnd],cx

	push	cx
	push	ds
	push	ax
	call	_ClearMemBlock
	pop	ax
	add	sp,4
	clc
loc_ex:
	pop	dx
	pop	cx
	pop	bp
	retn
loc_e:
	xor	ax,ax
	stc
	jmp	short loc_ex
_AllocHeap	endp

_ClearMemBlock	proc	near
	push	bp
	mov	bp,sp
	push	eax
	push	cx
	push	dx
	push	di
	push	es

	cld
	les	di,[bp+4]
	mov	cx,[bp+8]
	mov	dx,cx
	xor	eax,eax
	shr	cx,2
	jz	short loc_1
	rep	stosd
loc_1:
	mov	cx,dx
	and	cx,3
	jz	short loc_2
	rep	stosb
loc_2:
	pop	es
	pop	di
	pop	dx
	pop	cx
	pop	eax
	pop	bp
	retn
_ClearMemBlock	endp
_InitQueue	endp

;_AllocCtxHook	proc	near
;	mov	eax,offset CtxEntry
;	or	ebx,-1
;	mov	dl,DevHlp_AllocateCtxHook
;	call	dword ptr [DevHelp]
;	jc	short loc_e
;	mov	[CtxHandle],eax
;	mov	ax,1
;	retn
;loc_e:
;	xor	ax,ax
;	retn
;_AllocCtxHook	endp

_SetDrvEnv	proc	near
	push	esi
	xor	cx,cx
	mov	al,DHGETDOSV_SYSINFOSEG
	mov	dl,DevHlp_GetDOSVar
	call	dword ptr [DevHelp]
	jc	short loc_e
	mov	es,ax
	mov	ax,es:[bx]
	mov	[SysSel],ax

	xor	esi,esi
	mov	ax,ds
	mov	dl,DevHlp_VirtToLin
	call	dword ptr [DevHelp]
	jc	short loc_e
	mov	[DS_Lin],eax
	mov	ax,1
loc_ex:
	pop	esi
	retn
loc_e:
	xor	ax,ax
	jmp	short loc_ex
_SetDrvEnv	endp

_PutMessage	proc	near
	mov	bx,sp
	xor	ax,ax
	mov	bx,ss:[bx+2]
	mov	cx,256
	mov	dx,bx
loc_1:
	cmp	al,[bx]
	jz	short loc_3
	inc	bx
	dec	cx
	jnz	short loc_1
loc_2:
	retn
loc_3:
	sub	bx,dx
	jz	short loc_2
	push	1	; file handle (STDOUT)
	push	bx	; message length
	push	ds
	push	dx	; message buffer
	call	Dos16PutMessage
	retn
_PutMessage	endp

_TEXT	ends
end
