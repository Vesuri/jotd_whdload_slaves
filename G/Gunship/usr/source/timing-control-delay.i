; Native previous-control time horizon, standalone. Requires no game globals.
; A world tick reads current y plus y from the preceding world control sample.
; Preserve that horizon at field rate: 17 PAL fields or 20 NTSC fields.
; PAL rounds one-third second upward by 1/150 second; no accumulating drift.
CD_RATE equ 0
CD_LENGTH equ 2
CD_NEXT equ 4
CD_VALID equ 6
CD_FIELD equ 8
CD_SAMPLES equ 12
CD_SIZE equ 32             ; 20 signed direction bytes

; a0=state, d0=50/60 (3 whole-tick fixture), d1=initial previous y.
; Return 0/-1, preserving others. Initialize/rebase only at lifecycle boundary.
control_delay_init:
	movem.l d1-d3/a0,-(sp)
	cmpi.l #-1,d1
	blt .bad
	cmpi.l #1,d1
	bgt .bad
	moveq #17,d2
	cmpi.l #50,d0
	beq .valid
	moveq #20,d2
	cmpi.l #60,d0
	beq .valid
	moveq #1,d2
	cmpi.l #3,d0
	bne .bad
.valid:
	move.w d0,CD_RATE(a0)
	move.w d2,CD_LENGTH(a0)
	clr.l CD_NEXT(a0)
	clr.l CD_FIELD(a0)
	lea CD_SAMPLES(a0),a0
	moveq #19,d3
.fill:
	move.b d1,(a0)+
	dbf d3,.fill
	moveq #0,d0
	bra .done
.bad:
	moveq #-1,d0
.done:
	movem.l (sp)+,d1-d3/a0
	rts

; a0=PRIVATE working state, d0=field stamp, d1=current y (-1..1).
; Return d0=delayed y, d1=0 success; d0=0,d1=-1 failure without writes.
; Other registers preserved. Requires consecutive stamps, including wrap.
; Caller publishes this state only when the corresponding player step commits.
control_delay_step:
	movem.l d2-d5/a0-a1,-(sp)
	cmpi.l #-1,d1
	blt .bad
	cmpi.l #1,d1
	bgt .bad
	moveq #17,d2
	cmpi.w #50,CD_RATE(a0)
	beq .rate
	moveq #20,d2
	cmpi.w #60,CD_RATE(a0)
	beq .rate
	moveq #1,d2
	cmpi.w #3,CD_RATE(a0)
	bne .bad
.rate:
	cmp.w CD_LENGTH(a0),d2
	bne .bad
	moveq #0,d3
	move.w CD_NEXT(a0),d3
	cmp.w d2,d3
	bhs .bad
	cmpi.w #1,CD_VALID(a0)
	bhi .bad
	tst.w CD_VALID(a0)
	beq .first
	move.l CD_FIELD(a0),d4
	addq.l #1,d4
	cmp.l d0,d4
	bne .bad
.first:
	lea CD_SAMPLES(a0),a1
	move.b 0(a1,d3.w),d4
	ext.w d4
	ext.l d4
	cmpi.l #-1,d4
	blt .bad
	cmpi.l #1,d4
	bgt .bad
	move.b d1,0(a1,d3.w)
	addq.w #1,d3
	cmp.w d2,d3
	blo .store
	moveq #0,d3
.store:
	move.w d3,CD_NEXT(a0)
	move.w #1,CD_VALID(a0)
	move.l d0,CD_FIELD(a0)
	move.l d4,d0
	moveq #0,d1
	bra .done
.bad:
	moveq #0,d0
	moveq #-1,d1
.done:
	movem.l (sp)+,d2-d5/a0-a1
	rts
