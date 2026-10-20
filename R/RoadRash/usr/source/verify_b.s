; VERIFY-only B diagnostics, never included in release code.
verify_b_gate:
	move.w	sr,-(a7)
	movem.l	d0/a1,-(a7)
	lea	verify_b_stats(pc),a1
	addq.l	#1,8(a1)
	move.l	$a7266,a0
	tst.w	(a0)
	beq.b	.ready
	addq.l	#1,12(a1)
.ready:
	moveq	#0,d0
	move.w	$a6f00,d0
	cmp.w	#15,d0
	bls.b	.bin
	moveq	#15,d0
.bin:
	lsl.w	#2,d0
	addq.l	#1,32(a1,d0.w)
	movem.l	(a7)+,d0/a1
	move.w	(a7)+,ccr
	rts
verify_b_drain:
	move.w	sr,-(a7)
	movem.l	d0/a0,-(a7)
	lea	verify_b_stats(pc),a0
	addq.l	#1,16(a0)
	move.l	$a728a,a2
	moveq	#0,d0
	move.w	(a2),d0
	cmp.l	20(a0),d0
	bls.b	.no_max
	move.l	d0,20(a0)
.no_max:
	movem.l	(a7)+,d0/a0
	move.w	(a7)+,ccr
	move.l	$a726a,a2
	rts
	cnop	0,4
verify_b_stats:
	dc.b	'RRBSTAT1'
	dc.l	0,0,0,0,0,0
	ds.l	16
