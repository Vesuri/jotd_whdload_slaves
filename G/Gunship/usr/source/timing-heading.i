; Field heading/track, replacing stage 0's whole-tick angle writes.
; Requires timing-response.i and timing-fraction.i. Not installed.
HG_RATE equ 0
HG_HEADING equ 4
HG_HEADING_CONV equ 8
HG_TRACK equ 12
HG_TRACK_CONV equ 16
HG_SIZE equ 20
; Main fractions use 32767; conversion remainders use rate.
; Full retained angle = main/32767 + conversion/(rate*32767).

; a0=state, d0=50/60 or whole-tick fixture 3. d0=0/-1; others preserved.
heading_init:
	cmpi.l #50,d0
	beq .valid
	cmpi.l #60,d0
	beq .valid
	cmpi.l #3,d0
	bne .bad
.valid:
	clr.l (a0)
	move.w d0,HG_RATE(a0)
	clr.l HG_HEADING(a0)
	clr.l HG_HEADING_CONV(a0)
	clr.l HG_TRACK(a0)
	clr.l HG_TRACK_CONV(a0)
	moveq #0,d0
	rts
.bad:
	moveq #-1,d0
	rts

; a0=state, a1=private player AFTER native stage 0.
; d0=heading BEFORE stage 0 (0..255), d1=track BEFORE stage 0 (0..255),
; d2=supplied world heading impulse (-2..2), normally zero.
; Return d0=0/-1; other registers preserved. No RNG sampling.
; Grounded state freezes angles/fractions and requires zero supplied impulse.
heading_step:
	movem.l d1-d7/a0-a6,-(sp)
	cmpi.l #255,d0
	bhi .bad
	cmpi.l #255,d1
	bhi .bad
	cmpi.l #-2,d2
	blt .bad
	cmpi.l #2,d2
	bgt .bad
	move.l d0,d6
	move.l d1,d7
	movea.l d2,a6
	movea.l a0,a4
	movea.l a1,a5
	moveq #0,d2
	move.w HG_RATE(a4),d2
	cmpi.w #50,d2
	beq .rate_ok
	cmpi.w #60,d2
	beq .rate_ok
	cmpi.w #3,d2
	bne .bad
.rate_ok:
	lea .offsets(pc),a3
	moveq #1,d1
.validate_main:
	move.w (a3)+,d3
	move.l 0(a4,d3.w),d3
	cmpi.l #-32767,d3
	ble .bad
	cmpi.l #32767,d3
	bge .bad
	cmpi.w #3,d2
	bne .main_next
	tst.l d3
	bne .bad
.main_next:
	dbf d1,.validate_main
	moveq #1,d1
.validate_conv:
	move.w (a3)+,d3
	move.l 0(a4,d3.w),d3
	cmp.l d2,d3
	bge .bad
	move.l d2,d0
	neg.l d0
	cmp.l d0,d3
	ble .bad
	cmpi.w #3,d2
	bne .conv_next
	tst.l d3
	bne .bad
.conv_next:
	dbf d1,.validate_conv
	tst.w $1c(a5)
	bne .airborne
	move.l a6,d0
	tst.l d0
	bne .bad
	bra .ok
.airborne:
	move.b $36(a5),d0
	neg.b d0
	cmpi.b #4,d0
	bcc .bank
	; Hover/yaw branch: wrapping byte double, then scaled additive angle.
	move.b $3f(a5),d0
	add.b d0,d0
	ext.w d0
	ext.l d0
	lea HG_HEADING(a4),a0
	lea HG_HEADING_CONV(a4),a1
	bsr fraction_add_rate
	add.b d6,d0
	move.b d0,$35(a5)
	tst.b $37(a5)
	beq .yaw_track
	bmi .yaw_left
	addi.b #64,d0
	bra .yaw_track
.yaw_left:
	subi.b #64,d0
.yaw_track:
	move.b d0,$3d(a5)
	move.l HG_HEADING(a4),HG_TRACK(a4)
	move.l HG_HEADING_CONV(a4),HG_TRACK_CONV(a4)
	bra .impulse
.bank:
	move.b $37(a5),d5
	asr.b #2,d5
	ext.w d5
	ext.l d5
	; Native rounding bias wraps in BYTE width. Convert to an effective
	; word error so response_step's h=1 WORD bias produces the same result.
	move.b d7,d0
	sub.b d6,d0
	addq.b #8,d0
	ext.w d0
	ext.l d0
	subq.l #8,d0
	moveq #4,d1
	move.l HG_TRACK(a4),d3
	lea HG_HEADING(a4),a0
	bsr response_step_target
	move.l d0,d4
	move.l d5,d0
	lea HG_HEADING_CONV(a4),a1
	bsr fraction_add_rate
	add.b d4,d0
	add.b d6,d0
	move.b d0,$35(a5)
	clr.b $3f(a5)
	; Track sees the newly scaled heading, including its main fraction.
	move.b $35(a5),d0
	sub.b d7,d0
	addq.b #2,d0
	ext.w d0
	ext.l d0
	subq.l #2,d0
	moveq #2,d1
	move.l HG_HEADING(a4),d3
	lea HG_TRACK(a4),a0
	bsr response_step_target
	move.l d0,d4
	move.l d5,d0
	lea HG_TRACK_CONV(a4),a1
	bsr fraction_add_rate
	add.b d4,d0
	add.b d7,d0
	move.b d0,$3d(a5)
.impulse:
	; Native damage impulse happens AFTER the track calculation.
	move.l a6,d0
	add.b d0,$35(a5)
.ok:
	moveq #0,d0
	bra .done
.bad:
	moveq #-1,d0
.done:
	movem.l (sp)+,d1-d7/a0-a6
	rts
.offsets:
	dc.w HG_HEADING,HG_TRACK,HG_HEADING_CONV,HG_TRACK_CONV
