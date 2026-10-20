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
