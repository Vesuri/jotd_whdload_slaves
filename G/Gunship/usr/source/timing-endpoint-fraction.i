; Exact field distribution of a native tick delta. Standalone, not installed.
; Unlike response substeps, held input must reach the native tick endpoint.
; The caller previews from an interval anchor with fresh input every field.
; PAL delivers 17/17/16 fields per interval; NTSC delivers 20.
; 1360 = lcm(16,17,20), so fractions survive changes of interval length.
EF_DEN equ 1360

; a0 -> long remainder in [0,1360), initially zero.
; d0.l = native candidate minus interval anchor, in [-65535,65535].
; Circular coordinates/angles must already use their shortest signed delta.
; d1.l = delivered interval length: 16,17,20, or 1 for native-step tests.
; Returns d0.l integer increment (floor), d1.l status 0/-1.
; Other registers preserved. Invalid input returns zero without state writes.
; The caller adds the increment modulo the native field width. This primitive
; does not own player records, commands, world impulses or interval rebasing.
endpoint_fraction_step:
	movem.l d2-d4,-(sp)
	move.l (a0),d4
	cmpi.l #EF_DEN,d4
	bhs .bad
	cmpi.l #-65535,d0
	blt .bad
	cmpi.l #65535,d0
	bgt .bad
	cmpi.l #1,d1
	beq .whole
	moveq #85,d2
	cmpi.l #16,d1
	beq .scale
	moveq #80,d2
	cmpi.l #17,d1
	beq .scale
	moveq #68,d2
	cmpi.l #20,d1
	bne .bad
.scale:
	move.l d0,d3
	; A validated remainder is less than one unit. With no new motion,
	; the increment is zero and the residue stays unchanged; avoid MUL/DIV.
	beq .whole
	bpl .positive
	neg.l d0
.positive:
	mulu.w d2,d0
	tst.l d3
	bpl .add
	neg.l d0
.add:
	add.l d4,d0
	; |delta| <=65535 and factor <=85 keep quotient inside a signed word.
	divs.w #EF_DEN,d0
	move.l d0,d4
	ext.l d0
	swap d4
	ext.l d4
	bpl .store
	subq.l #1,d0
	addi.l #EF_DEN,d4
.store:
	move.l d4,(a0)
.whole:
	moveq #0,d1
	bra .done
.bad:
	moveq #0,d0
	moveq #-1,d1
.done:
	movem.l (sp)+,d2-d4
	rts
