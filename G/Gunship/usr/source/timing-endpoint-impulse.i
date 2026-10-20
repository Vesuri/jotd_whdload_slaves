; Apply a complete native disturbance difference at a world deadline.
; Requires endpoint-motion/player. Standalone; no RNG or scheduling.
;
; a0=EP owner, a1=PRIVATE completed endpoint player,
; a2=native h=1 candidate WITHOUT impulses, a3=matching candidate WITH them.
; Both candidates must use the same anchor, controls, tick and world inputs.
; Return 0/-1; other registers preserved. Invalid phase/residues write nothing.
; Caller generates impulses once, validates candidates, and publishes this
; private result transactionally before ground resolution. No replay guard here.
endpoint_impulse_apply:
	movem.l d1-d7/a0-a6,-(sp)
	move.w EP_SPAN(a0),d0
	cmpi.w #1,d0
	beq .span
	cmpi.w #16,d0
	beq .span
	cmpi.w #17,d0
	beq .span
	cmpi.w #20,d0
	bne .bad
.span:
	cmp.w EP_DONE(a0),d0
	bne .bad
	movea.l a0,a4
	movea.l a1,a5
	movea.l a3,a6
	movea.l a2,a1
	movea.l a3,a2
	movea.l a5,a3
	moveq #1,d0
	bsr endpoint_motion_step
	tst.l d0
	bne .done
	; Native height arithmetic floors a negative signed-word result to zero.
	; A changed-input endpoint may be nearer that floor than either preview.
	tst.w $1c(a5)
	bpl .height_ok
	clr.w $1c(a5)
	clr.l 8(a4)
.height_ok:
	; A difference between bounded native candidates need not keep a
	; changed-input endpoint bounded. Native clamps BEFORE signed wind.
	movea.l a4,a0
	movea.l a5,a1
	moveq #0,d1
	tst.w $1c(a5)
	beq .x_wind
	move.b $14(a5),d1
	ext.w d1
.x_wind:
	bsr .coordinate
	addq.l #4,a0
	addq.l #2,a1
	moveq #0,d1
	tst.w $1c(a5)
	beq .y_wind
	move.b $15(a5),d1
	ext.w d1
.y_wind:
	bsr .coordinate
	; The disturbance is a full difference, never 1/span. With held input
	; the base endpoint equals the undisturbed candidate exactly.
	; A changed-input path can already be closer to the roll limit than
	; the anchor preview. Retain native saturation on the actual result.
	cmpi.b #-20,$37(a5)
	blt .low
	cmpi.b #20,$37(a5)
	bgt .high
	bne .derived
	tst.l 32(a4)
	beq .derived
.high:
	move.b #20,$37(a5)
	clr.l 32(a4)
	bra .derived
.low:
	move.b #-20,$37(a5)
	clr.l 32(a4)
.derived:
	move.w $30(a6),$30(a5)
	move.b $38(a6),$38(a5)
	move.b $3a(a6),$3a(a5)
	move.b $3f(a6),$3f(a5)
	move.b $40(a6),$40(a5)
	move.b $50(a6),$50(a5)
	moveq #0,d0
	bra .done
.bad:
	moveq #-1,d0
.done:
	movem.l (sp)+,d1-d7/a0-a6
	rts

; a0=nonnegative fraction, a1=coordinate, d1.w=signed wind (zero on ground).
.coordinate:
	move.w (a1),d0
	sub.w d1,d0
	cmpi.w #$1800,d0
	blo .low_coordinate
	cmpi.w #$d800,d0
	blo .store_coordinate
	move.w #$d800,d0
	bra .discard_coordinate
.low_coordinate:
	move.w #$1800,d0
.discard_coordinate:
	clr.l (a0)
.store_coordinate:
	add.w d1,d0
	move.w d0,(a1)
	rts
