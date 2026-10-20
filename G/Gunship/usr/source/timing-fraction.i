; Signed rational increment with retained remainder. Standalone 68000 core.
; a0 -> signed long remainder, initially zero; denominator must stay fixed
; for this state until explicitly reset at initialization/rebase/impulse.
; d0.l = signed-word native increment, d1.l = numerator, d2.l = denominator.
; Require 0 <= numerator <= denominator <= 32767, denominator nonzero,
; and -denominator < remainder < denominator.
; Returns d0.l = signed integer increment, d1.l = 0 success / -1 invalid.
; On invalid input d0=0, no state write. Preserves d2-d7/a0-a6.
; CCR unspecified. Quotient truncates toward zero; remainder retains sign.
; Rates use 3/50 or 3/60 exactly. This does not define a decay coefficient
; or decide which native quantities are rates, impulses or derived values.

fraction_scale:
	movem.l d2-d4,-(sp)
	move.w d0,d3
	ext.l d3
	cmp.l d0,d3
	bne .bad
	tst.l d2
	ble .bad
	cmpi.l #32767,d2
	bhi .bad
	cmp.l d2,d1
	bhi .bad
	move.l (a0),d4
	cmp.l d2,d4
	bge .bad
	neg.l d2
	cmp.l d2,d4
	ble .bad
	neg.l d2
	; Bounds above keep product+remainder in signed long and quotient
	; in signed word, including -32768 with numerator=denominator.
	muls.w d1,d0
	add.l d4,d0
	divs.w d2,d0
	move.l d0,d3
	ext.l d0
	swap d3
	ext.l d3
	move.l d3,(a0)
	moveq #0,d1
	bra .done
.bad:
	moveq #0,d0
	moveq #-1,d1
.done:
	movem.l (sp)+,d2-d4
	rts

; Add a 3/rate linear increment into denominator-32767 fractional state.
; a0 -> main signed fraction; a1 -> signed conversion remainder (den=rate).
; d0.l signed-word increment, d2.l rate (3..32767).
; Returns d0 integer increment, d1 status 0/-1. Preserves d2-d7/a0-a6.
; Total retained state is main/32767 + conversion/(rate*32767).
; This lets an additive slew share an approach response's main fraction.
fraction_add_rate:
	movem.l d2-d6,-(sp)
	move.w d0,d3
	ext.l d3
	cmp.l d0,d3
	bne .bad
	cmpi.l #3,d2
	blo .bad
	cmpi.l #32767,d2
	bhi .bad
	move.l (a0),d5
	cmpi.l #-32767,d5
	ble .bad
	cmpi.l #32767,d5
	bge .bad
	move.l (a1),d6
	cmp.l d2,d6
	bge .bad
	move.l d2,d3
	neg.l d3
	cmp.l d3,d6
	ble .bad
	; Divide in native units first so neither quotient exceeds a word.
	muls.w #3,d0
	divs.w d2,d0
	move.w d0,d4
	ext.l d4
	swap d0
	ext.l d0
	muls.w #32767,d0
	add.l d6,d0
	divs.w d2,d0
	move.l d0,d3
	swap d3
	ext.l d3
	move.l d3,(a1)
	ext.l d0
	add.l d5,d0
	divs.w #32767,d0
	move.l d0,d3
	swap d3
	ext.l d3
	move.l d3,(a0)
	ext.l d0
	add.l d4,d0
	moveq #0,d1
	bra .done
.bad:
	moveq #0,d0
	moveq #-1,d1
.done:
	movem.l (sp)+,d2-d6
	rts
