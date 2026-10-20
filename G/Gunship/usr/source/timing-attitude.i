; Continuous stick attitude with optional externally supplied world impulses.
; Never samples gameplay RNG or decides impulse eligibility.
; Requires timing-fraction.i. Standalone; not installed in gameplay.
AT_RATE equ 0             ; word: 50 PAL, 60 NTSC, 3 whole-tick test mode
AT_PREVIOUS_Y equ 2       ; signed word: preceding consumed field's y
AT_ROLL_REMAINDER equ 4   ; signed long, denominator AT_RATE
AT_PITCH_REMAINDER equ 8  ; signed long, denominator AT_RATE
AT_SIZE equ 12

; a0=state, d0=rate, d1=previous y (-1..1).
; d0=0 success/-1 invalid (no writes); other registers preserved.
attitude_init:
	cmpi.l #-1,d1
	blt .bad
	cmpi.l #1,d1
	bgt .bad
	cmpi.l #50,d0
	beq .valid
	cmpi.l #60,d0
	beq .valid
	cmpi.l #3,d0
	bne .bad
.valid:
	move.w d0,AT_RATE(a0)
	move.w d1,AT_PREVIOUS_Y(a0)
	clr.l AT_ROLL_REMAINDER(a0)
	clr.l AT_PITCH_REMAINDER(a0)
	moveq #0,d0
	rts
.bad:
	moveq #-1,d0
	rts

; a0=state, a1=player, d0=x (-1..1), d1=y (-1..1).
; d0=0 success/-1 invalid (no writes); preserves d1-d7/a0-a6.
; Native roll adds 4*x and clamps after byte wrapping.
; Native pitch subtracts current+previous y only when current y is nonzero.
; The separate authoritative pitch clamp is NOT a render/attitude side effect.
attitude_step:
	movem.l d2-d3,-(sp)
	moveq #0,d2
	moveq #0,d3
	bsr attitude_step_impulses
	movem.l (sp)+,d2-d3
	rts

; Same API, plus d2.l=roll impulse (-4/0/+4), d3.l=pitch impulse (-1/0/+1).
; Caller generates eligible impulses once at the world boundary.
; Impulses are NOT time-scaled: roll combines before clamp, pitch after
; continuous control. Ordinary fields pass zero (attitude_step above).
attitude_step_impulses:
	movem.l d1-d7/a0-a6,-(sp)
	cmpi.l #-4,d2
	beq .roll_impulse_ok
	tst.l d2
	beq .roll_impulse_ok
	cmpi.l #4,d2
	bne .bad
.roll_impulse_ok:
	cmpi.l #-1,d3
	blt .bad
	cmpi.l #1,d3
	bgt .bad
	move.l d2,d5
	movea.l d3,a3
	cmpi.l #-1,d0
	blt .bad
	cmpi.l #1,d0
	bgt .bad
	cmpi.l #-1,d1
	blt .bad
	cmpi.l #1,d1
	bgt .bad
	moveq #0,d2
	move.w AT_RATE(a0),d2
	cmpi.w #50,d2
	beq .rate_ok
	cmpi.w #60,d2
	beq .rate_ok
	cmpi.w #3,d2
	bne .bad
.rate_ok:
	move.w AT_PREVIOUS_Y(a0),d7
	ext.l d7
	cmpi.l #-1,d7
	blt .bad
	cmpi.l #1,d7
	bgt .bad
	move.l AT_ROLL_REMAINDER(a0),d3
	move.l AT_PITCH_REMAINDER(a0),d4
	cmp.l d2,d3
	bge .bad
	cmp.l d2,d4
	bge .bad
	neg.l d2
	cmp.l d2,d3
	ble .bad
	cmp.l d2,d4
	ble .bad
	neg.l d2
	movea.l a0,a4
	movea.l a1,a5
	move.l d1,d6
	lsl.l #2,d0
	lea AT_ROLL_REMAINDER(a4),a0
	moveq #3,d1
	bsr fraction_scale
	add.b $37(a5),d0
	add.b d5,d0
	cmpi.b #-20,d0
	blt .roll_low
	cmpi.b #20,d0
	bgt .roll_high
	; Discard only outward debt at saturation, so reversal is immediate.
	beq .upper_edge
	cmpi.b #-20,d0
	bne .roll_store
	tst.l AT_ROLL_REMAINDER(a4)
	bmi .roll_reset
	bra .roll_store
.upper_edge:
	tst.l AT_ROLL_REMAINDER(a4)
	bgt .roll_reset
	bra .roll_store
.roll_low:
	moveq #-20,d0
	bra .roll_reset
.roll_high:
	moveq #20,d0
.roll_reset:
	clr.l AT_ROLL_REMAINDER(a4)
.roll_store:
	move.b d0,$37(a5)
	moveq #0,d0
	tst.l d6
	beq .pitch
	move.l d6,d0
	add.l d7,d0
	neg.l d0
.pitch:
	lea AT_PITCH_REMAINDER(a4),a0
	moveq #3,d1
	bsr fraction_scale
	add.b d0,$36(a5)
	move.l a3,d0
	add.b d0,$36(a5)
	move.w d6,AT_PREVIOUS_Y(a4)
	moveq #0,d0
	bra .done
.bad:
	moveq #-1,d0
.done:
	movem.l (sp)+,d1-d7/a0-a6
	rts
