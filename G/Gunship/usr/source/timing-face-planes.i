; Read-only reduction from native +068f8..+0691c, not installed.
; a0=aligned plane records (nx,ny,nz,distance: four signed words each),
; d0=unsigned plane count 0..255, d1/d2/d3=signed-word transformed X/Y/Z.
; Return 0 at least one facing plane, 1 no facing planes, 2 no planes,
; -1 malformed scalar argument. Preserve every other register; no writes
; except stack. Caller owns plane memory and native coordinate preparation.
; Zero planes in +06818 leave the shared flight-end flag unchanged, so 2 is
; explicitly not a collision result. Multiple native shapes overwrite that
; flag rather than ORing it. Shape selection/aggregation remain unresolved.
; Preserve MULS.W, 32-bit wrapping sums and CMP.L/SMI (N flag, NOT signed LT).
face_planes_classify:
	movem.l d1-d7/a0,-(sp)
	cmpi.l #255,d0
	bhi .bad
	move.w d1,d4
	ext.l d4
	cmp.l d1,d4
	bne .bad
	move.w d2,d4
	ext.l d4
	cmp.l d2,d4
	bne .bad
	move.w d3,d4
	ext.l d4
	cmp.l d3,d4
	bne .bad
	tst.l d0
	beq .empty
	move.l d0,d7
	subq.w #1,d7
	moveq #0,d6
.loop:
	move.w (a0)+,d4
	muls.w d1,d4
	move.w (a0)+,d5
	muls.w d2,d5
	add.l d5,d4
	move.w (a0)+,d5
	muls.w d3,d5
	add.l d5,d4
	move.w (a0)+,d5
	ext.l d5
	cmp.l d4,d5
	smi d5
	or.b d5,d6
	dbf d7,.loop
	moveq #0,d0
	tst.b d6
	seq d0
	andi.w #1,d0
	bra .done
.empty:
	moveq #2,d0
	bra .done
.bad:
	moveq #-1,d0
.done:
	movem.l (sp)+,d1-d7/a0
	rts
