; Standalone native camera/instrument builder. Not installed yet.
; a0 = player record, a1 = hunk-6 instrument block +157d (16 bytes),
; a2 = camera vector (12 bytes), a3 = native interpolation table hunk4+1c8.
; All registers preserved, CCR unspecified. Player state is read-only.
; Pitch clamping belongs to the player update, not repeated rendering.

presentation_build:
	movem.l d0-d4/a0-a3,-(sp)
	move.b 4(a0),d0
	lsr.b #2,d0
	bsr .gauge
	ori.b #$80,d0
	move.b d0,0(a1)
	move.b 6(a0),d0
	lsr.b #2,d0
	bsr .gauge
	ori.b #$80,d0
	move.b d0,1(a1)
	move.b $39(a0),d0
	lsr.b #1,d0
	bsr .gauge
	move.b d0,d1
	move.b d0,d2
	btst #2,$42(a0)
	bne .engine1
	clr.b d1
.engine1:
	move.b d1,2(a1)
	btst #3,$42(a0)
	bne .engine2
	clr.b d2
.engine2:
	move.b d2,3(a1)
	move.b $1b(a0),d0
	lsr.b #3,d0
	bsr .gauge
	move.b d0,5(a1)
	move.b $35(a0),9(a1)
	move.b $36(a0),11(a1)
	move.b $37(a0),d0
	neg.b d0
	move.b d0,12(a1)
	btst #4,$0f(a0)
	beq .undamaged
	moveq #6,d1
.damage:
	move.b #$80,0(a1,d1.w)
	dbf d1,.damage
.undamaged:
	move.b $2b(a0),d0
	sub.b $50(a0),d0
	move.b d0,13(a1)
	move.w $1c(a0),d0
	move.w d0,d1
	lsr.w #2,d1
	add.w d1,d0
	move.w d0,7(a1)
	move.b $3e(a0),d0
	lsl.w #8,d0
	asr.w #1,d0
	; Native +07a1c interpolation, including rounding from the shifted bit.
	clr.w d2
	move.b d0,d2
	lsr.w #7,d0
	bclr #0,d0
	move.w 2(a3,d0.w),d1
	move.w 0(a3,d0.w),d0
	sub.w d0,d1
	muls.w d2,d1
	asr.l #8,d1
	bcc .rounded
	addq.w #1,d1
.rounded:
	add.w d1,d0
	lsr.w #8,d0
	move.b d0,15(a1)
	bsr native_camera_build
	movem.l (sp)+,d0-d4/a0-a3
	rts
.gauge:
	move.b d0,d2
	lsr.b #1,d2
	add.b d2,d0
	cmpi.b #32,d0
	bcs .gauge_done
	move.b #31,d0
.gauge_done:
	rts

; Native +057E2 camera only, for committed-state geometry and presentation.
; a0=player, a2=12-byte destination. All registers preserved.
; Preserve byte wrapping and NEG-before-ASR for native half-pitch.
native_camera_build:
	move.l d0,-(sp)
	move.w 0(a0),0(a2)
	move.w 2(a0),2(a2)
	move.w $1c(a0),d0
	addi.w #24,d0
	move.w d0,4(a2)
	move.b $35(a0),d0
	add.b $1a(a0),d0
	neg.b d0
	lsl.w #8,d0
	move.w d0,6(a2)
	move.b $36(a0),d0
	neg.b d0
	asr.b #1,d0
	lsl.w #8,d0
	move.w d0,8(a2)
	move.b $37(a0),d0
	neg.b d0
	lsl.w #8,d0
	move.w d0,10(a2)
	move.l (sp)+,d0
	rts

; Exact native +05756..+05776 clamp, including BMI after byte subtraction.
; a0 = player record. All registers preserved; CCR unspecified.
; Must be scheduled explicitly relative to control/recoil, never per render.
player_pitch_clamp:
	move.l d0,-(sp)
	move.b $36(a0),d0
	cmpi.b #-12,d0
	bmi .low
	cmpi.b #20,d0
	blt .store
	move.b #20,d0
	bra .store
.low:
	move.b #-12,d0
.store:
	move.b d0,$36(a0)
	move.l (sp)+,d0
	rts
