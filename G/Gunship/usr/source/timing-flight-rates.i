; Stage-connected vertical, forward and RPM rates. Standalone, not installed.
; Requires timing-response.i and timing-fraction.i.
FR_RATE equ 0
FR_VERTICAL equ 4
FR_FORWARD equ 8
FR_FORWARD_CONV equ 12
FR_RPM equ 16
FR_RPM_CONV equ 20
FR_SIZE equ 24
; Main fractions have denominator 32767; conversion fractions have rate.
; Full fraction = main/32767 + conversion/(rate*32767).
; Initialize/reset alongside native state. Ground resets must clear vertical
; and BOTH forward fractions. All fields belong in the lifecycle manifest.

; a0=state, d0=50/60 (field) or 3 (whole-tick fixture).
; d0=0 success/-1 invalid; other registers preserved.
flight_rates_init:
	cmpi.l #50,d0
	beq .valid
	cmpi.l #60,d0
	beq .valid
	cmpi.l #3,d0
	bne .bad
.valid:
	clr.l (a0)
	move.w d0,FR_RATE(a0)
	clr.l FR_VERTICAL(a0)
	clr.l FR_FORWARD(a0)
	clr.l FR_FORWARD_CONV(a0)
	clr.l FR_RPM(a0)
	clr.l FR_RPM_CONV(a0)
	moveq #0,d0
	rts
.bad:
	moveq #-1,d0
	rts

; a0=state, a1=private player, a2=native stage-1 terms.
; Replace stage 1's whole vertical update BEFORE running height stage 2.
; d0=0/-1; all other registers preserved.
flight_vertical_step:
	movem.l d1-d7/a0-a6,-(sp)
	movea.l a0,a4
	movea.l a1,a5
	move.w 2(a2),d6
	ext.l d6
	move.w 6(a2),d7
	ext.l d7
	cmpi.l #-128,d6
	blt .bad
	cmpi.l #127,d6
	bgt .bad
	cmpi.l #-128,d7
	blt .bad
	cmpi.l #127,d7
	bgt .bad
	bsr flight_rates_check
	tst.l d0
	bne .bad
	lea FR_VERTICAL(a4),a0
	move.l d6,d0
	sub.l d7,d0
	moveq #2,d1
	bsr response_step_native
	tst.l d1
	bne .bad
	add.b d7,d0
	move.b d0,$3e(a5)
	moveq #0,d0
	bra .done
.bad:
	moveq #-1,d0
.done:
	movem.l (sp)+,d1-d7/a0-a6
	rts

; a0=state, a1=private player, a2=native stage-3 error/slew terms.
; REPLACES stage 4; stage 5 then reads the resulting forward speed.
flight_forward_step:
	movem.l d1-d7/a0-a6,-(sp)
	movea.l a0,a4
	movea.l a1,a5
	move.w 2(a2),d6
	ext.l d6
	move.w 6(a2),d7
	ext.l d7
	cmpi.l #-1,d7
	blt .bad
	cmpi.l #1,d7
	bgt .bad
	bsr flight_rates_check
	tst.l d0
	bne .bad
	lea FR_FORWARD(a4),a0
	move.l d6,d0
	moveq #4,d1
	bsr response_step_native
	tst.l d1
	bne .bad
	move.l d0,d6
	lea FR_FORWARD_CONV(a4),a1
	move.l d7,d0
	bsr fraction_add_rate
	; Preconditions for fraction_add_rate were checked before any write.
	add.w d6,d0
	add.w $2a(a5),d0
	move.w d0,$2a(a5)
	moveq #0,d0
	bra .done
.bad:
	moveq #-1,d0
.done:
	movem.l (sp)+,d1-d7/a0-a6
	rts

; a0=state, a1=private player AFTER stage 6, d0=RPM byte BEFORE stage 6.
; Replace stage 6's whole update; target/derived inputs remain native.
flight_rpm_step:
	movem.l d1-d7/a0-a6,-(sp)
	cmpi.l #255,d0
	bhi .bad
	move.l d0,d7
	movea.l a0,a4
	movea.l a1,a5
	bsr flight_rates_check
	tst.l d0
	bne .bad
	btst #4,$42(a5)
	beq .coast
	moveq #0,d0
	move.b $40(a5),d0
	sub.l d7,d0
	moveq #3,d1
	lea FR_RPM(a4),a0
	bsr response_step_native
	tst.l d1
	bne .bad
	add.b d7,d0
	bra .store
.coast:
	; Native unclamped additive change. Do not scale the clamped endpoint.
	moveq #0,d0
	move.b $39(a5),d0
	lsr.w #2,d0
	move.l d7,d6
	sub.l d0,d6
	beq .coast_speed
	tst.w $1c(a5)
	bne .coast_speed
	subq.l #1,d6
.coast_speed:
	move.b $50(a5),d0
	ext.w d0
	asr.w #3,d0
	ext.l d0
	add.l d6,d0
	sub.l d7,d0
	lea FR_RPM(a4),a0
	lea FR_RPM_CONV(a4),a1
	bsr fraction_add_rate
	add.l d7,d0
	bmi .low
	cmpi.l #156,d0
	bgt .high
	beq .upper_edge
	tst.l d0
	bne .store
	move.l FR_RPM(a4),d3
	bne .lower_sign
	move.l FR_RPM_CONV(a4),d3
.lower_sign:
	tst.l d3
	bmi .saturate
	bra .store
.upper_edge:
	move.l FR_RPM(a4),d3
	bne .upper_sign
	move.l FR_RPM_CONV(a4),d3
.upper_sign:
	tst.l d3
	bgt .saturate
	bra .store
.low:
	moveq #0,d0
	bra .saturate
.high:
	move.l #156,d0
.saturate:
	clr.l FR_RPM(a4)
	clr.l FR_RPM_CONV(a4)
.store:
	move.b d0,$1b(a5)
	moveq #0,d0
	bra .done
.bad:
	moveq #-1,d0
.done:
	movem.l (sp)+,d1-d7/a0-a6
	rts

; Internal: a4=state, d0=0/-1, d2=rate; clobbers d1/d3/a3.
; Check every fraction before a component may commit any write.
flight_rates_check:
	moveq #0,d2
	move.w FR_RATE(a4),d2
	cmpi.w #50,d2
	beq .rate_ok
	cmpi.w #60,d2
	beq .rate_ok
	cmpi.w #3,d2
	bne .bad
.rate_ok:
	lea .main_offsets(pc),a3
	moveq #2,d1
.main:
	move.w (a3)+,d3
	move.l 0(a4,d3.w),d3
	cmpi.l #-32767,d3
	ble .bad
	cmpi.l #32767,d3
	bge .bad
	cmpi.w #3,d2
	bne .next_main
	tst.l d3
	bne .bad
.next_main:
	dbf d1,.main
	moveq #1,d1
.conversion:
	move.w (a3)+,d3
	move.l 0(a4,d3.w),d3
	cmp.l d2,d3
	bge .bad
	move.l d2,d0
	neg.l d0
	cmp.l d0,d3
	ble .bad
	cmpi.w #3,d2
	bne .next_conversion
	tst.l d3
	bne .bad
.next_conversion:
	dbf d1,.conversion
	moveq #0,d0
	rts
.bad:
	moveq #-1,d0
	rts
.main_offsets:
	dc.w FR_VERTICAL,FR_FORWARD,FR_RPM
	dc.w FR_FORWARD_CONV,FR_RPM_CONV
