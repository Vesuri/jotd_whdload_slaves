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

; Scheduled authoritative pitch clamp, before this field's stick/motion.
; a0=attitude state, a1=player; d0=0/-1, other registers preserved.
; Native byte/BMI semantics are deliberate (including extreme byte values).
; Clear stale pitch debt after an actual clamp, or outward debt exactly at
; a limit. Preserve inward debt so reversing controls is not delayed.
attitude_pitch_clamp:
	movem.l d1-d3,-(sp)
	moveq #0,d3
	move.w AT_RATE(a0),d3
	cmpi.w #50,d3
	beq .rate
	cmpi.w #60,d3
	beq .rate
	cmpi.w #3,d3
	bne .bad
.rate:
	move.l AT_PITCH_REMAINDER(a0),d0
	cmp.l d3,d0
	bge .bad
	neg.l d3
	cmp.l d3,d0
	ble .bad
	move.b $36(a1),d1
	move.b d1,d2
	cmpi.b #-12,d1
	bmi .low
	cmpi.b #20,d1
	blt .check
	move.b #20,d1
	bra .check
.low:
	move.b #-12,d1
.check:
	cmp.b d2,d1
	bne .clear
	cmpi.b #-12,d1
	bne .upper
	tst.l d0
	bmi .clear
	bra .store
.upper:
	cmpi.b #20,d1
	bne .store
	tst.l d0
	ble .store
.clear:
	clr.l AT_PITCH_REMAINDER(a0)
.store:
	move.b d1,$36(a1)
	moveq #0,d0
	bra .done
.bad:
	moveq #-1,d0
.done:
	movem.l (sp)+,d1-d3
	rts

; Combined-player pre-clamp, a2=immutable control packet (signed y at +2).
; Field steps must retain native held-input endpoints: native clamp followed
; by delta=-(y+previous_y) can reach +22/-14. Clamping to +20/-12 every
; field would instead converge to +20+2*h / -12-2*h.
; Extend only the outward pre-clamp bound by delta*(1-h), h=3/rate.
; The following scaled attitude step then reaches the native endpoint.
; Release/reversal restores the corresponding original pre-clamp bound.
; World impulses are applied later, unchanged. Whole-tick mode uses the
; original byte/BMI clamp exactly. Return 0/-1; preserve other registers.
attitude_pitch_clamp_control:
	movem.l d1-d6,-(sp)
	moveq #0,d2
	move.w AT_RATE(a0),d2
	cmpi.w #3,d2
	beq .whole
	cmpi.w #50,d2
	beq .rate
	cmpi.w #60,d2
	bne .bad
.rate:
	move.w 2(a2),d3
	cmpi.w #-1,d3
	blt .bad
	cmpi.w #1,d3
	bgt .bad
	move.w AT_PREVIOUS_Y(a0),d4
	cmpi.w #-1,d4
	blt .bad
	cmpi.w #1,d4
	bgt .bad
	tst.w d3
	beq .delta
	add.w d4,d3
	neg.w d3
.delta:
	move.l AT_PITCH_REMAINDER(a0),d1
	cmp.l d2,d1
	bge .bad
	move.l d2,d4
	neg.l d4
	cmp.l d4,d1
	ble .bad
	moveq #0,d0
	move.b $36(a1),d0
	ext.w d0
	muls.w d2,d0
	add.l d1,d0
	moveq #-12,d4
	muls.w d2,d4
	moveq #20,d5
	muls.w d2,d5
	move.w d2,d6
	subq.w #3,d6
	muls.w d3,d6
	tst.w d3
	bmi .lower
	add.l d6,d5
	bra .clamp
.lower:
	add.l d6,d4
.clamp:
	cmp.l d4,d0
	blt .low
	cmp.l d5,d0
	ble .ok
	move.l d5,d0
	bra .store
.low:
	move.l d4,d0
.store:
	divs.w d2,d0
	move.b d0,$36(a1)
	swap d0
	ext.l d0
	move.l d0,AT_PITCH_REMAINDER(a0)
.ok:
	moveq #0,d0
	bra .done
.whole:
	bsr attitude_pitch_clamp
	bra .done
.bad:
	moveq #-1,d0
.done:
	movem.l (sp)+,d1-d6
	rts
