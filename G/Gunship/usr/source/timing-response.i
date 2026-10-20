; Fraction-aware native approach response. Standalone; not installed.
; a0 -> signed long fractional state, denominator 32767, initially zero.
; d0.l = signed-word target-minus-integer-state error (native units).
; d1.l = native response shift: 2 (quarter), 3 (eighth), 4 (sixteenth).
; d2.l = field rate 50/60, or 3 for the exact whole-tick fixture.
; d0.l = integer increment, d1.l = 0 success / -1 invalid (no state write).
; Preserves d2-d7/a0-a6; CCR unspecified.
; Caller adds the increment to the native integer state with native width.
; Speed's separate slew and unpowered RPM do NOT use this response law.
RS_DEN equ 32767

response_step:
	move.l d3,-(sp)
	moveq #0,d3
	bsr response_step_target
	move.l (sp)+,d3
	rts

; Same API, with d3.l = target's fraction (denominator 32767).
; This supports a moving fractional target, e.g. track following heading.
; The target's smaller rate-conversion residue, if any, remains caller-owned.
response_step_target:
	movem.l d2-d7/a1-a2,-(sp)
	cmpi.l #-RS_DEN,d3
	ble .bad
	cmpi.l #RS_DEN,d3
	bge .bad
	movea.l d3,a2
	move.w d0,d3
	ext.l d3
	cmp.l d0,d3
	bne .bad
	cmpi.l #2,d1
	blo .bad
	cmpi.l #4,d1
	bhi .bad
	move.l (a0),d4
	cmpi.l #-RS_DEN,d4
	ble .bad
	cmpi.l #RS_DEN,d4
	bge .bad
	cmpi.l #3,d2
	beq .whole
	cmpi.l #50,d2
	beq .pal
	cmpi.l #60,d2
	bne .bad
	moveq #12,d6
	bra .coefficient
.pal:
	moveq #0,d6
.coefficient:
	move.l d1,d5
	subq.w #2,d5
	add.w d5,d5
	add.w d5,d5
	add.w d6,d5
	lea response_gains(pc),a1
	adda.w d5,a1
	move.w (a1),d5
	move.w 2(a1),d6
	move.l d0,d2
	; Gain has 16 fractional bits beyond the denominator-32767 numerator.
	; Products truncate below one residual unit, not one native state unit.
	; Feedback includes the retained fraction, not merely integer error.
	move.l d4,d0
	bsr .gain_product
	divs.w #RS_DEN,d0
	ext.l d0
	move.l d0,d4
	move.l a2,d0
	bsr .gain_product
	divs.w #RS_DEN,d0
	ext.l d0
	sub.l d0,d4
	move.l d2,d0
	bsr .gain_product
	add.l (a0),d0
	sub.l d4,d0
	divs.w #RS_DEN,d0
	move.l d0,d3
	ext.l d0
	swap d3
	ext.l d3
	move.l d3,(a0)
	moveq #0,d1
	bra .done
.whole:
	; Whole-tick equivalence starts from native integer state, no fractions.
	; Preserve the native WORD add of rounding bias before arithmetic shift.
	tst.l d4
	bne .bad
	move.l a2,d3
	tst.l d3
	bne .bad
	moveq #1,d5
	lsl.w d1,d5
	lsr.w #1,d5
	add.w d5,d0
	asr.w d1,d0
	ext.l d0
	moveq #0,d1
	bra .done
.bad:
	moveq #0,d0
	moveq #-1,d1
.done:
	movem.l (sp)+,d2-d7/a1-a2
	rts
.gain_product:
	; d0 signed word * (d5 unsigned high word + d6 unsigned fraction).
	; Return truncation toward zero in d0; clobbers d3/d7.
	move.w d0,d3
	ext.l d3
	bpl .positive
	neg.w d0
.positive:
	move.w d0,d7
	mulu.w d6,d0
	swap d0
	andi.l #$ffff,d0
	mulu.w d5,d7
	add.l d7,d0
	tst.l d3
	bpl .product_done
	neg.l d0
.product_done:
	rts

; round(65536 * 32767 * (1 - (1 - 2^-shift)^(3/rate))).
; PAL shift 2/3/4, then NTSC shift 2/3/4.
; Native rate-3 fixture takes the exact integer path above.
response_gains:
	dc.l $0230bc42,$010579fe,$007ea380
	dc.l $01d3f349,$00da0adf,$006990f7
