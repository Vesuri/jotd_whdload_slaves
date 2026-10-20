; Renderer-only angle adapter for endpoint-player's denominator-1360 residues.
; Apply after native_camera_build/presentation_build. Not installed.
; a0=player, a1=EP state, a2=12-byte camera.
; Return 0/-1; preserve others. No player/shadow writes. Invalid rate or angle
; fractions leave camera unchanged. Native rate-3 fixture requires zero angle
; fractions and preserves native byte negation/half-pitch rounding exactly.
endpoint_camera_angles:
	movem.l d1-d6,-(sp)
	move.w EP_DELAY+CD_RATE(a1),d6
	cmpi.w #50,d6
	beq .validate
	cmpi.w #60,d6
	beq .validate
	cmpi.w #3,d6
	bne .bad
.validate:
	move.l 20(a1),d1
	move.l 28(a1),d2
	move.l 32(a1),d3
	cmpi.l #EF_DEN,d1
	bhs .bad
	cmpi.l #EF_DEN,d2
	bhs .bad
	cmpi.l #EF_DEN,d3
	bhs .bad
	cmpi.w #3,d6
	bne .angles
	move.l d1,d0
	or.l d2,d0
	or.l d3,d0
	bne .bad
.angles:
	moveq #0,d4
	move.b $35(a0),d4
	add.b $1a(a0),d4
	lsl.w #8,d4
	moveq #0,d5
	move.b $36(a0),d5
	neg.b d5
	cmpi.w #3,d6
	bne .fractional
	asr.b #1,d5
	lsl.w #8,d5
	bra .roll
.fractional:
	lsl.l #8,d1
	divu.w #EF_DEN,d1
	add.w d1,d4
	ext.w d5
	lsl.w #7,d5
	lsl.l #7,d2
	divu.w #EF_DEN,d2
	sub.w d2,d5
.roll:
	moveq #0,d6
	move.b $37(a0),d6
	neg.b d6
	lsl.w #8,d6
	lsl.l #8,d3
	divu.w #EF_DEN,d3
	sub.w d3,d6
	neg.w d4
	move.w d4,6(a2)
	move.w d5,8(a2)
	move.w d6,10(a2)
	moveq #0,d0
	bra .done
.bad:
	moveq #-1,d0
.done:
	movem.l (sp)+,d1-d6
	rts
