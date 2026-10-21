; Diagnostic-only instrumentation. Included exclusively by IFD VERIFY.
; ABI is big endian, version 1. Host discovers the RRA1STAT marker in slave RAM.
; Timing counters are cheap; requested state hashing is a separate correctness run.
; Normal builds contain neither hooks nor this storage. No game behaviour fixes here.
	IFND VERIFY_HASH_FIELD
VERIFY_HASH_FIELD = 0
	ENDC
	IFD VERIFY_MMU_POLICY
	IFND VERIFY_MMU
	FAIL "MMU policy capture requires VERIFY_MMU"
	ENDC
	ENDC

verify_start:
	movem.l	d0/a0,-(a7)
	lea	verify_stats(pc),a0
	bsr	verify_cacr
	move.l	d0,8(a0)
	movem.l	(a7)+,d0/a0
	rts

verify_cacr:
	moveq	#-1,d0
	btst	#1,verify_attn+3(pc) ; AFF_68020; never execute MOVEC on 68000/010
	beq.b	.done
	dc.w	$4e7a,$0002         ; movec CACR,d0 (assembler remains 68000)
.done:
	rts

; SetCPU returns the previous WHDLoad policy in d0; record it alongside the
; actual post-call CACR. A separate sidecar preserves the A-series ABI.
verify_cpu_set:
	movem.l d0/a0,-(a7)
	lea verify_cpu_setup(pc),a0
	move.l d0,8(a0)
	bsr verify_cacr
	move.l d0,12(a0)
	addq.l #1,16(a0)
	movem.l (a7)+,d0/a0
	rts

verify_field:
	addq.l	#1,$a5d4c          ; displaced instruction, including its CCR
public_ref_9 equ *-4
	move.w	sr,-(a7)
	movem.l	d0-d2/a0-a1,-(a7)
	lea	verify_stats(pc),a0
	tst.l	16(a0)
	bne.b	.seen
	bsr	verify_cacr
	move.l	d0,12(a0)
	move.w	$dff002,20(a0)      ; DMACONR, not write-only DMACON
	IFD VERIFY_MMU
	btst	#3,verify_attn+3(pc) ; AFF_68040, also set on 060
	beq.b	.no_tc
	dc.w	$4e7a,$0003         ; movec TC,d0 (040/060 only)
	move.l	d0,40(a0)
	IFD VERIFY_MMU_POLICY
	lea verify_mmu_policy+8(pc),a1
	dc.w $4e7a,$0807        ; SRP
	move.l d0,(a1)+
	dc.w $4e7a,$0806        ; URP
	move.l d0,(a1)+
	dc.w $4e7a,$0004        ; ITT0
	move.l d0,(a1)+
	dc.w $4e7a,$0005        ; ITT1
	move.l d0,(a1)+
	dc.w $4e7a,$0006        ; DTT0
	move.l d0,(a1)+
	dc.w $4e7a,$0007        ; DTT1
	move.l d0,(a1)+
	ENDC
.no_tc:
	move.l	verify_attn(pc),44(a0)
	ENDC
.seen:
	move.l	$a5d4c,16(a0)
public_ref_10 equ *-6
	move.l	48(a0),d0          ; requested exact race field, zero disables hashing
	beq.b	.done
	cmp.l	16(a0),d0
	bne.b	.done
	moveq	#0,d0
	lea	$a5d4c,a1          ; clock plus complete actor storage through $a6edf
public_ref_11 equ *-4
	move.w	#($a6ee0-$a5d4c)/2-1,d2
	bsr.b	.hash
	lea	$a7220,a1          ; nearest-rider rank/speed cells
public_ref_12 equ *-4
	moveq	#3,d2
	bsr.b	.hash
	lea	$a59f4,a1          ; displayed player rank
public_ref_13 equ *-4
	moveq	#0,d2
	bsr.b	.hash
	move.l	d0,56(a0)
	move.l	16(a0),52(a0)      ; publish field last
	clr.l	48(a0)
.done:
	movem.l	(a7)+,d0-d2/a0-a1
	move.w	(a7)+,ccr
	rts
.hash:
	rol.l	#5,d0
	moveq	#0,d1
	move.w	(a1)+,d1
	eor.l	d1,d0
	dbf	d2,.hash
	rts

verify_frame:
	move.w	sr,-(a7)
	movem.l	d0-d1/a0,-(a7)
	lea	verify_stats(pc),a0
	addq.l	#1,24(a0)
	move.l	$a5d4c,d0
public_ref_14 equ *-4
	move.l	d0,d1
	sub.l	28(a0),d0
	move.l	d1,28(a0)
	cmp.l	#63,d0
	bls.b	.bin
	moveq	#63,d0             ; overflow bucket includes first-frame startup interval
.bin:
	lsl.w	#2,d0
	addq.l	#1,64(a0,d0.w)
	move.w	$dff002,22(a0)
	movem.l	(a7)+,d0-d1/a0
	move.w	(a7)+,ccr
	move.l	$a7266,a2          ; displaced MOVEA leaves CCR unchanged
public_ref_15 equ *-4
	rts

	cnop	0,4
verify_stats:
	dc.b	'RRA1STAT'          ; +0 marker
	dc.l	-1,-1              ; +8 startup CACR, +12 race CACR (-1 = unsupported)
	dc.l	0                  ; +16 last race field
	dc.w	0,0                ; +20 first race / +22 last frame DMACONR
	dc.l	0,0                ; +24 frame count, +28 last frame race field
	dc.l	1,320,-1,0         ; +32 ABI version, +36 size, +40 TC, +44 AttnFlags
	dc.l	VERIFY_HASH_FIELD,0,0 ; +48 hash request, +52 field, +56 hash
	IFD VERIFY_MMU
	dc.l	1                  ; +60 flags: bit 0 = TC snapshot enabled
	ELSE
	dc.l	0
	ENDC
	ds.l	64                 ; +64 frame-duration histogram; bucket 63 = overflow
	IFD VERIFY_MMU_POLICY
; Optional sidecar preserves the existing 320-byte RRA1STAT ABI.
verify_mmu_policy:
	dc.b "RRCMMU01"
	dc.l 0,0,0,0,0,0       ; SRP, URP, ITT0/1, DTT0/1
	ENDC
verify_cpu_setup:
	dc.b "RRDCPU01"
	dc.l -1,-1,0 ; previous SetCPU policy, post-call CACR, calls
	IFD C_STEP_BUILD
verify_c_selection:
	dc.b	"RRCSEL01"
	dc.l	0,0,0,0            ; Custom2, AttnFlags, slave base, reason
	ENDC

; Functional timing tests only. The display swap still uses the original path.
	IFD VERIFY_FRAME_PERIOD
verify_pace:
	IFD VERIFY_FRAME_PATTERN
	movem.l d0/a0,-(a7)
	lea verify_period_index(pc),a0
	moveq #0,d0
	move.w (a0),d0
	addq.w #1,(a0)
	andi.w #7,(a0)
	lea verify_period_pattern(pc),a0
	move.b (a0,d0.w),d0
	subq.b #1,d0
.wait:
	cmp.b $aec0c,d0
public_ref_16 equ *-4
	bhi .wait
	movem.l (a7)+,d0/a0
	ELSE
	cmpi.b	#VERIFY_FRAME_PERIOD-1,$aec0c
public_ref_237 equ *-4
	bcs.b	verify_pace
	ENDC
	IFND C_STEP_BUILD
	movem.l	d0,-(a7)
	move.l	_enhanced_framerate(pc),d0
	movem.l	(a7)+,d0             ; retain MOVE's zero flag
	beq.b	.original
	bra	safe_swap
	ENDC
.original:
	jmp	$aecba
public_ref_17 equ *-4
	IFD VERIFY_FRAME_PATTERN
verify_period_index:
	dc.w 0
verify_period_pattern:
	dc.b 1,2,3,4,12,2,16,4
	even
	ENDC
	ENDC
