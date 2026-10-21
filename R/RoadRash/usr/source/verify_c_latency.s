; Optional C probe: first RIGHT input after reset, through the first frame built
; from its simulation result. All timestamps are active PAL fields, not host
; time. Swap return measures buffer handoff, not completion of screen scanout.
; Use STEP_NO_HASH and STEP_CAPTURE=0 for hardware-cost measurements.
step_latency_reset:
	lea step_latency_stats+8(pc),a0
	moveq #14-1,d0
.clear:
	clr.l (a0)+
	dbf d0,.clear
	rts

step_latency_input:
	movem.l d0/a0,-(a7)
	lea step_latency_stats(pc),a0
	tst.l 8(a0)
	bne .done
	btst #3,$a598c
public_ref_latency_0 equ *-4
	beq .done
	move.l $a5d4c,8(a0)
public_ref_latency_1 equ *-6
	moveq #0,d0
	move.b $a598c,d0
public_ref_latency_2 equ *-4
	move.l d0,56(a0)
	move.l $a5d4c,d0
public_ref_latency_3 equ *-4
	sub.l step_stats+8(pc),d0
	move.l d0,60(a0)
.done:
	movem.l (a7)+,d0/a0
	rts

step_latency_replayed:
	movem.l d0/a0,-(a7)
	lea step_latency_stats(pc),a0
	tst.l 8(a0)
	beq .done
	tst.l 12(a0)
	bne .done
	btst #3,$a598c
public_ref_latency_4 equ *-4
	beq .done
	move.l $a5d4c,12(a0)
public_ref_latency_5 equ *-6
	move.l d3,16(a0)
	move.w $a7262,d0
public_ref_latency_6 equ *-4
	ext.l d0
	move.l d0,48(a0)
.done:
	movem.l (a7)+,d0/a0
	rts

step_latency_simulated:
	movem.l a0,-(a7)
	lea step_latency_stats(pc),a0
	tst.l 12(a0)
	beq .done
	tst.l 20(a0)
	bne .done
	move.l $a5d4c,20(a0)
public_ref_latency_7 equ *-6
	move.l step_stats+8(pc),24(a0)
.done:
	movem.l (a7)+,a0
	rts

step_latency_render:
	movem.l d0/a0,-(a7)
	lea step_latency_stats(pc),a0
	tst.l 20(a0)
	beq .done
	tst.l 28(a0)
	bne .done
	move.l $a5d4c,28(a0)
public_ref_latency_8 equ *-6
	move.l step_stats+8(pc),32(a0)
	move.w $a5d60,d0
public_ref_latency_9 equ *-4
	ext.l d0
	move.l d0,52(a0)
.done:
	movem.l (a7)+,d0/a0
	jmp $8970e
public_ref_latency_10 equ *-4

step_latency_swap:
	movem.l a0,-(a7)
	lea step_latency_stats(pc),a0
	tst.l 28(a0)
	beq .wait
	tst.l 40(a0)
	bne .wait
	move.l $a5d4c,36(a0)
public_ref_latency_11 equ *-6
.wait:
	movem.l (a7)+,a0
	IFD VERIFY_FRAME_PERIOD
	bsr verify_pace
	ELSE
	jsr $aecba
public_ref_latency_12 equ *-4
	ENDC
	movem.l a0,-(a7)
	lea step_latency_stats(pc),a0
	tst.l 36(a0)
	beq .done
	tst.l 40(a0)
	bne .done
	move.l $a5d4c,40(a0)
public_ref_latency_13 equ *-6
	move.l $404,44(a0)
.done:
	movem.l (a7)+,a0
	rts

	cnop 0,4
step_latency_stats:
	dc.b "RRCLAT01"
; +8 input field, +12 replay live field, +16 replay historical field,
; +20 simulation end live field, +24 simulation cursor,
; +28 render start live field, +32 rendered simulation cursor,
; +36 swap entry field, +40 swap return field, +44 front-buffer pointer,
; +48 steering after replay, +52 rendered lateral position, +56 raw input,
; +60 simulation debt when the input was polled.
	ds.l 14
