; Candidate only: normalized player heading and conserved ground displacement.
; Not enabled in the normal runtime. Crash/skid semantics still need auditing.
	IFND VERIFY
	FAIL "Steering candidate is diagnostic only"
	ENDC
	IFNE STEP_FIELDS-1
	FAIL "Steering candidate requires one-field simulation"
	ENDC

step_steering_heading:
	move.l $26(a1),d0
	lsr.l #8,d0
	move.l d0,d1
	tst.b $6e(a1)
	bpl .native
; Heading/pose uses the existing four-field timing reference. The second
; movement factor in d1 remains the actual one-field travelled distance.
	moveq #0,d0
	move.w $12(a1),d0
	lsl.l #2,d0
	lsr.l #8,d0
.native:
	muls.w $42(a1),d0
	asr.l #8,d0
	move.w d0,$c(a1)
	jmp $8b94c

step_steering_motion:
	muls.w d1,d0
	tst.b $6e(a1)
	bpl .native
	btst #5,$68(a1)
	bne .native
; Original ground displacement truncates twice: /256 then *13/16.
; Preserve the combined fraction. With one-field unsigned 16-bit speed,
; the movement factor is <=255; multiplying its signed-word product by 13
; fits a signed long. Truncate toward zero symmetrically on both sides.
	movem.l d1-d2/a0,-(a7)
	lea step_steering_fraction(pc),a0
	move.l d0,d2
	lsl.l #3,d0
	add.l d2,d0
	lsl.l #2,d2
	add.l d2,d0
	add.l (a0),d0
	move.l d0,d1
	bpl .positive
	neg.l d0
.positive:
	move.l d0,d2
	andi.l #4095,d2
	lsr.l #8,d0
	lsr.l #4,d0
	tst.l d1
	bpl .store
	neg.l d0
	neg.l d2
.store:
	move.l d2,(a0)
	movem.l (a7)+,d1-d2/a0
	jmp $8b9a0
.native:
	move.l a0,-(a7)
	lea step_steering_fraction(pc),a0
	clr.l (a0)
	move.l (a7)+,a0
	asr.l #8,d0
	btst #5,$68(a1)
	jmp $8b984

	cnop 0,4
step_steering_fraction:
	dc.l 0
