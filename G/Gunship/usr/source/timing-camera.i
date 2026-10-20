; Fractional player camera angles. Requires player-step state constants.
; Standalone; not installed. Apply after presentation_build to replace only
; the three angle words. No simulation/player/shadow writes or RNG calls.
; a0=player, a1=PS_SIZE state, a2=12-byte camera vector.
; d0=0/-1; other registers preserved. Invalid angle state leaves output alone.
; Field mode removes the native pitch half-angle staircase. Fixture rate 3
; preserves native byte-negation/ASR exactly and requires zero fractions.
player_camera_angles:
	movem.l d1-d7/a0-a6,-(sp)
	movea.l a0,a5
	movea.l a1,a4
	movea.l a2,a6
	lea PS_KINEMATICS+KN_HEADING(a4),a3
	moveq #0,d2
	move.w AT_RATE(a4),d2
	cmp.w HG_RATE(a3),d2
	bne .bad
	cmpi.w #50,d2
	beq .rate_ok
	cmpi.w #60,d2
	beq .rate_ok
	cmpi.w #3,d2
	bne .bad
.rate_ok:
	move.l AT_ROLL_REMAINDER(a4),d0
	bsr .small_fraction
	bne .bad
	move.l AT_PITCH_REMAINDER(a4),d0
	bsr .small_fraction
	bne .bad
	move.l HG_HEADING_CONV(a3),d0
	bsr .small_fraction
	bne .bad
	move.l HG_HEADING(a3),d0
	cmpi.l #-32767,d0
	ble .bad
	cmpi.l #32767,d0
	bge .bad
	cmpi.w #3,d2
	bne .angles
	tst.l d0
	bne .bad
.angles:
	moveq #0,d4
	move.b $35(a5),d4
	add.b $1a(a5),d4
	lsl.w #8,d4
	move.b $36(a5),d5
	neg.b d5
	move.b $37(a5),d6
	neg.b d6
	lsl.w #8,d6
	cmpi.w #3,d2
	beq .native
	; trunc((main*rate+conversion)*256 / (32767*rate)).
	; Two truncating divisions are exact for the integer quotient here.
	; First quotient fits signed word: abs(value) < rate*256 <= 15360.
	move.l HG_HEADING(a3),d0
	muls.w d2,d0
	add.l HG_HEADING_CONV(a3),d0
	lsl.l #8,d0
	divs.w #32767,d0
	ext.l d0
	divs.w d2,d0
	add.w d0,d4
	; Linear half-pitch, retaining the native byte-negation wrap.
	ext.w d5
	lsl.w #7,d5
	move.l AT_PITCH_REMAINDER(a4),d0
	lsl.l #7,d0
	divs.w d2,d0
	sub.w d0,d5
	move.l AT_ROLL_REMAINDER(a4),d0
	lsl.l #8,d0
	divs.w d2,d0
	sub.w d0,d6
	bra .store
.native:
	asr.b #1,d5
	lsl.w #8,d5
.store:
	neg.w d4
	move.w d4,6(a6)
	move.w d5,8(a6)
	move.w d6,10(a6)
	moveq #0,d0
	bra .done
.bad:
	moveq #-1,d0
.done:
	movem.l (sp)+,d1-d7/a0-a6
	rts
; Check signed fraction against rate; fixture mode requires zero.
; d0=input, d1=scratch. Returns Z=1 valid, Z=0 invalid.
.small_fraction:
	cmp.l d2,d0
	bge .invalid
	move.l d2,d1
	neg.l d1
	cmp.l d1,d0
	ble .invalid
	cmpi.w #3,d2
	bne .valid
	tst.l d0
	bne .invalid
.valid:
	moveq #0,d1
	rts
.invalid:
	moveq #-1,d1
	rts
