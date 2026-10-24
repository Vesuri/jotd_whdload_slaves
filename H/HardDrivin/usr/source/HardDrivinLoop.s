; Arcade handling on the loop (CUSTOM1=2). The loop is a 12-sided polygon of
; road sections, 30 degrees each, whose edges all point the same way: a
; cylinder, along which the road moves sideways by its width. The native pass
; moves the car in a straight line for a whole step, a 68000 frame being more
; than one facet at the real scale, so its wheel-height pitch cannot follow.
; Here, after each step's physics, the car is put back on the surface: it
; advances along the facets by the step's distance and moves sideways by its
; heading relative to the road (a car going straight goes round a circle, so
; the road's drift needs the wheel, as in the arcade's demo), its pitch
; is interpolated between the facets' midpoints and its heading, pitch and
; roll are composed from that pitch and the relative heading. It lets go
; halfway along the flat sections either side, off the road's edge, when
; v^2/r no longer holds the car against gravity, and on a crash.
; See ARCADE_HANDLING_PLAN.md, H3 round 10.

LP_ACTIVE equ 0		; w: nonzero while the car is held on the loop
LP_J equ 2		; w: facet 0..13, from section LP_BASE+20*J to the next
LP_FRAC equ 4		; w: unsigned Q16 position along the facet
LP_PSI equ 6		; w: heading relative to the road, G($994A) units
LP_H0 equ 8		; w: the road's heading
LP_L equ 10		; l: sideways offset from the centre line, Q4 units
LP_BASE equ 14		; l: the flat section before the loop
LP_AXIS equ 18		; 3 w: the sections' edge direction, Q14
LP_G equ 24		; w: facet J's length round the loop, Q4 units
LP_FA equ 26		; w: facet J's centre line drift along LP_AXIS, Q4 units
LP_SECTION equ 28	; l: the road section pointer the loop last wrote
LP_THETA equ 32		; w: the loop's pitch at the car
LP_SINE equ 34		; w: its sine, Q14, for the model's gravity
LP_SIZE equ 36

LOOP_HALF equ 115*16	; half the road's width, Q4
LOOP_LIFT equ 24*8	; off the surface when it lets go, X8 units: past the wheels
			; of a pitch up to 15 degrees off the facet's
LOOP_HOLD equ 253	; (ft/s per v)^-2 x 1 g x ft per unit x r/G, see below

_loop_state: dcb.b LP_SIZE,0

; The rest of the slave is out of PC-relative reach: \2 = address of \1.
LOOP_FAR macro
	lea _loop_state(pc),\2
	adda.l #\1-_loop_state,\2
	endm

; Called after each step's physics, before drawing. Preserves all registers.
_loop_step:
	movem.l d0-d7/a0-a3,-(a7)
	lea _loop_state(pc),a2
	LOOP_FAR _flight_release,a0
	clr.w (a0)
	LOOP_FAR _contact_arcade,a0
	move.w (a0),d0
	beq .done
	bsr _loop_floor
	tst.b -$69fa(a4)		; crash countdown
	bne .release
	tst.w LP_ACTIVE(a2)
	bne .held
	bsr _loop_enter
	beq .done
	bra .pose
.held:
	; the pass may move the road pointer a section or two; recovery or
	; another writer moves it further
	move.l -$671c(a4),d0
	sub.l LP_SECTION(a2),d0
	cmpi.l #60,d0
	bgt .release
	cmpi.l #-60,d0
	blt .release
	; the heading relative to the road moves the car along and across
	move.w LP_PSI(a2),d0
	bsr _loop_cos
	move.w d0,d6
	move.w LP_PSI(a2),d0
	bsr _loop_sin
	move.w d0,d7
	; distance, Q4 units: 3v/128 a field (the native 1.5 v per 8-field step)
	move.w -$66d8(a4),d0		; velocity G($9928)
	LOOP_FAR _time_scalar_fields,a0
	muls.w (a0),d0
	move.l d0,d1
	add.l d0,d0
	add.l d1,d0
	asr.l #3,d0
	move.w d0,d1
	muls.w d7,d1
	asr.l #7,d1
	asr.l #7,d1
	add.l d1,LP_L(a2)		; across
	muls.w d6,d0
	asr.l #7,d0
	asr.l #7,d0			; along, Q4
	bsr _loop_advance
	beq .release
	cmpi.w #13,LP_J(a2)
	bne.s .edge
	tst.w LP_FRAC(a2)
	bmi .release_posed		; halfway along the flat section after it
.edge:
	move.l LP_L(a2),d0
	bpl.s .positive
	neg.l d0
.positive:
	cmpi.l #LOOP_HALF,d0
	bgt .fall			; off the side
.pose:
	bsr _loop_theta
	move.w LP_THETA(a2),d0
	bsr _loop_sin
	move.w d0,LP_SINE(a2)
	; held while v^2 >= g r (-cos theta), with v = 0.2099 ft/s a unit,
	; 0.1791 ft a unit and r = G / (2 sin 15 degrees): v^2 >= 253 G (-cos)
	move.w LP_THETA(a2),d0
	bsr _loop_cos
	neg.w d0
	ble.s .pressed
	move.w LP_G(a2),d1
	mulu.w #LOOP_HOLD,d1
	lsr.l #4,d1
	mulu.w d0,d1
	moveq #14,d0
	lsr.l d0,d1
	move.w -$66d8(a4),d0
	muls.w d0,d0
	cmp.l d1,d0
	blo .fall			; too slow to stay on
.pressed:
	bsr _loop_pose
	bra .done
.fall:
	; off the surface and into the ballistic flight, at any pitch
	bsr _loop_theta
	bsr _loop_pose
	bsr _loop_lift
	clr.b -$66f0(a4)		; no wheel down
	LOOP_FAR _flight_release,a0
	move.w #1,(a0)
	bra.s .release
.release_posed:
	bsr _loop_theta
	bsr _loop_pose
.release:
	clr.w LP_ACTIVE(a2)
.done:
	movem.l (a7)+,d0-d7/a0-a3
	rts

; A2 = state. Return Z clear when the car has just reached the loop: on the
; ground, going forward, past halfway along the flat section before it.
_loop_enter:
	tst.b -$66f0(a4)		; contact mask G($9910)
	beq .no
	tst.w -$66d8(a4)
	ble .no
	; a native section search that finds no candidate ($de92) stores its
	; uninitialised local, as _checkpoint_post notes: only a section in
	; the road's list, with the two after it
	move.l -$671c(a4),d0
	btst #0,d0
	bne .no
	movea.l d0,a0
	cmpa.l -$6720(a4),a0		; first section G($98e0)
	blo .no
	movea.l -$50da(a4),a1
	tst.b -$66b0(a4)
	beq.s .list
	movea.l -$50d6(a4),a1
.list:
	lea 60(a0),a3
	cmpa.l a1,a3
	bhi .no
	tst.w 14(a0)
	bne .no
	cmpi.w #60,20+14(a0)
	bne .no
	cmpi.w #180,40+14(a0)
	bne .no
	move.l a0,LP_BASE(a2)
	; the edge direction, Q14, from the first loop section
	lea 20(a0),a1
	move.w 6(a1),d0
	sub.w (a1),d0
	move.w 8(a1),d1
	sub.w 2(a1),d1
	move.w 10(a1),d2
	sub.w 4(a1),d2
	move.w d0,d3
	muls.w d3,d3
	move.w d1,d4
	muls.w d4,d4
	add.l d4,d3
	move.w d2,d4
	muls.w d4,d4
	add.l d4,d3
	move.l d3,d0
	bsr _loop_sqrt
	move.w d0,d3			; the road's width
	beq .no
	move.w 6(a1),d0
	sub.w (a1),d0
	bsr .axis
	move.w d0,LP_AXIS(a2)
	move.w 8(a1),d0
	sub.w 2(a1),d0
	bsr .axis
	move.w d0,LP_AXIS+2(a2)
	move.w 10(a1),d0
	sub.w 4(a1),d0
	bsr .axis
	move.w d0,LP_AXIS+4(a2)
	move.w 12(a1),d0		; the road's heading
	bsr _loop_wrap
	move.w d0,LP_H0(a2)
	clr.w LP_J(a2)
	bsr _loop_facet
	; how far along the flat section, Q16
	bsr _loop_offset		; D0-D2 = car - centre line start, Q4
	move.l d0,d3
	move.l d1,d4
	move.l d2,d5
	bsr _loop_along
	cmpi.l #$8000,d0
	blt.s .no
	cmpi.l #$ffff,d0
	bgt.s .no
	move.w d0,LP_FRAC(a2)
	; across: what is left of the offset, along the edges
	move.l d3,d0
	move.l d4,d1
	move.l d5,d2
	bsr _loop_dot_axis
	move.l d0,LP_L(a2)
	move.w -$66b6(a4),d0		; heading G($994A)
	sub.w LP_H0(a2),d0
	bsr _loop_wrap
	move.w d0,LP_PSI(a2)
	move.w #1,LP_ACTIVE(a2)
	moveq #1,d0
	rts
.no:
	moveq #0,d0
	rts
; D0 = edge component, D3 = width: D0 = Q14 unit component
.axis:
	ext.l d0
	moveq #14,d4
	asl.l d4,d0
	divs.w d3,d0
	rts

; A2 = state, LP_J set: LP_G and LP_FA for that facet.
_loop_facet:
	bsr _loop_section
	bsr _loop_centre
	move.l d0,d3
	move.l d1,d4
	move.l d2,d5
	lea 20(a0),a0
	bsr _loop_centre_a0
	sub.l d3,d0
	sub.l d4,d1
	sub.l d5,d2			; the centre line, Q4
	movem.l d0-d2,-(a7)
	bsr _loop_dot_axis
	move.w d0,LP_FA(a2)
	move.l d0,d3
	movem.l (a7)+,d0-d2
	; round the loop: less the drift along the edges
	move.w LP_AXIS(a2),d4
	muls.w d3,d4
	asr.l #7,d4
	asr.l #7,d4
	sub.l d4,d0
	move.w LP_AXIS+2(a2),d4
	muls.w d3,d4
	asr.l #7,d4
	asr.l #7,d4
	sub.l d4,d1
	move.w LP_AXIS+4(a2),d4
	muls.w d3,d4
	asr.l #7,d4
	asr.l #7,d4
	sub.l d4,d2
	muls.w d0,d0
	muls.w d1,d1
	muls.w d2,d2
	add.l d1,d0
	add.l d2,d0
	bsr _loop_sqrt
	tst.w d0
	bne.s .length
	moveq #1,d0
.length:
	move.w d0,LP_G(a2)
	rts

; A2 = state: A0 = facet LP_J's first section.
_loop_section:
	movea.l LP_BASE(a2),a0
	move.w LP_J(a2),d0
	mulu.w #20,d0
	adda.l d0,a0
	rts
; A0 = section: D0-D2 = the centre of its edge, Q4 units.
_loop_centre:
_loop_centre_a0:
	move.w (a0),d0
	ext.l d0
	move.w 6(a0),d6
	ext.l d6
	add.l d6,d0
	asl.l #3,d0
	move.w 2(a0),d1
	ext.l d1
	move.w 8(a0),d6
	ext.l d6
	add.l d6,d1
	asl.l #3,d1
	move.w 4(a0),d2
	ext.l d2
	move.w 10(a0),d6
	ext.l d6
	add.l d6,d2
	asl.l #3,d2
	rts
; A2 = state: D0-D2 = the car's position less facet LP_J's centre start, Q4.
_loop_offset:
	bsr _loop_section
	bsr _loop_centre
	move.l -$6704(a4),d3		; position X8 G($98FC)
	add.l d3,d3
	sub.l d3,d0
	neg.l d0
	move.l -$6700(a4),d3
	add.l d3,d3
	sub.l d3,d1
	neg.l d1
	move.l -$66fc(a4),d3
	add.l d3,d3
	sub.l d3,d2
	neg.l d2
	rts
; D0-D2 = Q4 vector: D0 = its component along LP_AXIS, Q4. Clobbers D1-D2/D6.
_loop_dot_axis:
	move.w LP_AXIS(a2),d6
	muls.w d6,d0
	move.w LP_AXIS+2(a2),d6
	muls.w d6,d1
	add.l d1,d0
	move.w LP_AXIS+4(a2),d6
	muls.w d6,d2
	add.l d2,d0
	asr.l #7,d0
	asr.l #7,d0
	rts
; D0-D2 = Q4 offset from the facet's start: D0 = Q16 fraction along the
; facet, round the loop (the offset less its drift, over the length).
_loop_along:
	movem.l d3-d5,-(a7)
	move.l d0,d3
	move.l d1,d4
	move.l d2,d5
	bsr _loop_dot_axis		; the offset along the edges
	move.w LP_AXIS(a2),d6
	muls.w d0,d6
	asr.l #7,d6
	asr.l #7,d6
	sub.l d6,d3
	move.w LP_AXIS+2(a2),d6
	muls.w d0,d6
	asr.l #7,d6
	asr.l #7,d6
	sub.l d6,d4
	move.w LP_AXIS+4(a2),d6
	muls.w d0,d6
	asr.l #7,d6
	asr.l #7,d6
	sub.l d6,d5
	; the facet's direction round the loop, over its length squared
	movem.l d3-d5,-(a7)
	bsr _loop_section
	bsr _loop_centre
	movem.l d0-d2,-(a7)
	lea 20(a0),a0
	bsr _loop_centre_a0
	sub.l (a7)+,d0
	sub.l (a7)+,d1
	sub.l (a7)+,d2
	move.w LP_FA(a2),d3
	move.w LP_AXIS(a2),d6
	muls.w d3,d6
	asr.l #7,d6
	asr.l #7,d6
	sub.l d6,d0
	move.w LP_AXIS+2(a2),d6
	muls.w d3,d6
	asr.l #7,d6
	asr.l #7,d6
	sub.l d6,d1
	move.w LP_AXIS+4(a2),d6
	muls.w d3,d6
	asr.l #7,d6
	asr.l #7,d6
	sub.l d6,d2
	movem.l (a7)+,d3-d5
	muls.w d3,d0
	muls.w d4,d1
	muls.w d5,d2
	add.l d1,d0
	add.l d2,d0			; offset . direction, Q8
	move.w LP_G(a2),d1
	divs.w d1,d0			; Q4 distance along it
	bvs.s .far
	ext.l d0
	bmi.s .behind
	cmp.w d1,d0
	bhs.s .far
	swap d0
	clr.w d0
	divu.w d1,d0
	andi.l #$ffff,d0
	bra.s .return
.behind:
	moveq #-1,d0
	bra.s .return
.far:
	move.l #$10000,d0
.return:
	movem.l (a7)+,d3-d5
	rts

; A2 = state, D0 = signed Q4 distance along the loop. Moves LP_J/LP_FRAC,
; takes the centre line's drift off LP_L. Returns Z set when the car has
; gone back off the start of the flat section before the loop.
_loop_advance:
	move.l d0,d3
.forward:
	tst.l d3
	ble.s .backward
	moveq #0,d0
	move.w LP_FRAC(a2),d0
	move.l #$10000,d4
	sub.l d0,d4			; the facet's part ahead, Q16
	mulu.w LP_G(a2),d0
	clr.w d0
	swap d0
	moveq #0,d1
	move.w LP_G(a2),d1
	sub.l d0,d1
	move.l d1,d0			; ahead, Q4
	cmp.l d0,d3
	blt.s .within
	sub.l d0,d3
	move.l d4,d0
	bsr .drift
	clr.w LP_FRAC(a2)
	addq.w #1,LP_J(a2)
	cmpi.w #13,LP_J(a2)
	bhi.s .past
	bsr .facet
	bra.s .forward
.past:
	move.w #13,LP_J(a2)
	move.w #$ffff,LP_FRAC(a2)
	bra.s .moved
.within:
	move.l d3,d0
	swap d0
	clr.w d0
	divu.w LP_G(a2),d0
	andi.l #$ffff,d0
	add.w d0,LP_FRAC(a2)
	bsr .drift
	bra.s .moved
.backward:
	tst.l d3
	beq.s .moved
	neg.l d3
.back:
	moveq #0,d0
	move.w LP_FRAC(a2),d0		; the facet's part behind, Q16
	move.l d0,d4
	mulu.w LP_G(a2),d0
	clr.w d0
	swap d0
	cmp.l d0,d3
	blt.s .back_within
	sub.l d0,d3
	move.l d4,d0
	neg.l d0
	bsr .drift
	tst.w LP_J(a2)
	beq.s .gone
	subq.w #1,LP_J(a2)
	bsr .facet
	move.w #$ffff,LP_FRAC(a2)
	bra.s .back
.back_within:
	move.l d3,d0
	swap d0
	clr.w d0
	divu.w LP_G(a2),d0
	andi.l #$ffff,d0
	sub.w d0,LP_FRAC(a2)
	neg.l d0
	bsr .drift
.moved:
	moveq #1,d0
	rts
.gone:
	moveq #0,d0
	rts
; the next facet's length and drift, keeping the distance left
.facet:
	movem.l d3-d5,-(a7)
	bsr _loop_facet
	movem.l (a7)+,d3-d5
	rts
; D0 = signed Q16 part of the facet travelled: LP_L -= that of its drift
.drift:
	move.w LP_FA(a2),d1
	ext.l d1
	moveq #0,d2
	tst.l d0
	bpl.s .part
	neg.l d0
	not.b d2
.part:
	tst.l d1
	bpl.s .fa
	neg.l d1
	not.b d2
.fa:
	cmpi.l #$ffff,d0
	bls.s .word
	move.l #$ffff,d0
.word:
	mulu.w d0,d1
	clr.w d1
	swap d1
	tst.b d2
	beq.s .sign
	neg.l d1
.sign:
	sub.l d1,LP_L(a2)
	rts

; A2 = state: LP_THETA, the pitch interpolated between the facets'
; midpoints at LP_J/LP_FRAC.
_loop_theta:
	bsr _loop_section
	move.w 14(a0),d1		; this facet's pitch
	moveq #0,d2
	move.w LP_FRAC(a2),d2
	subi.l #$8000,d2		; from its midpoint, Q16 of a facet
	bmi.s .before
	cmpi.l #$7fff,d2
	bls.s .after
	move.l #$7fff,d2
.after:
	move.w 20+14(a0),d0		; the next facet's
	bra.s .lerp
.before:
	neg.l d2
	cmpi.l #$7fff,d2
	bls.s .start
	move.l #$7fff,d2
.start:
	moveq #0,d0
	tst.w LP_J(a2)
	beq.s .lerp			; the flat section's own
	move.w -20+14(a0),d0		; the previous facet's
.lerp:
	sub.w d1,d0
	bsr _loop_wrap
	muls.w d2,d0
	swap d0
	add.w d1,d0
	bsr _loop_wrap
	move.w d0,LP_THETA(a2)
	rts

; A2 = state: writes the car's position on the facet, its angles, road
; section and a grounded contact state.
_loop_pose:
	bsr _loop_section
	move.l a0,LP_SECTION(a2)
	move.l a0,-$671c(a4)
	bsr _loop_centre
	movem.l d0-d2,-(a7)		; the facet's start
	lea 20(a0),a0
	bsr _loop_centre_a0
	movem.l (a7),d3-d5
	sub.l d3,d0
	sub.l d4,d1
	sub.l d5,d2			; its centre line, Q4
	moveq #0,d3
	move.w LP_FRAC(a2),d3
	bsr .scale
	move.l d0,d4
	move.l d1,d5
	move.l d2,d6
	movem.l (a7)+,d0-d2
	add.l d4,d0
	add.l d5,d1
	add.l d6,d2
	; across along the edges
	move.l LP_L(a2),d3
	asr.l #2,d3			; Q2 keeps the product in range
	move.w LP_AXIS(a2),d4
	muls.w d3,d4
	asr.l #6,d4
	asr.l #6,d4
	add.l d4,d0
	move.w LP_AXIS+2(a2),d4
	muls.w d3,d4
	asr.l #6,d4
	asr.l #6,d4
	add.l d4,d1
	move.w LP_AXIS+4(a2),d4
	muls.w d3,d4
	asr.l #6,d4
	asr.l #6,d4
	add.l d4,d2
	asr.l #1,d0			; X8
	asr.l #1,d1
	asr.l #1,d2
	move.l d0,-$6704(a4)		; G($98FC)
	move.l d1,-$6700(a4)
	move.l d2,-$66fc(a4)
	asr.l #3,d0
	move.w d0,-$670a(a4)		; G($98F6)
	asr.l #3,d1
	move.w d1,-$6708(a4)
	asr.l #3,d2
	move.w d2,-$6706(a4)
	bsr _loop_angles
	move.w d0,-$66b6(a4)		; heading G($994A)
	move.w d0,-$66bc(a4)		; G($9944)
	move.w d1,-$66b4(a4)		; pitch G($994C)
	move.w d1,-$66ba(a4)		; G($9946)
	move.w d2,-$66b2(a4)		; roll G($994E)
	move.w d2,-$66b8(a4)		; G($9948)
	lea _handling_state(pc),a0
	move.w d0,HS_LAST_HEAD(a0)
	clr.w -$66f2(a4)		; fall velocity G($990E)
	move.b #15,-$66f0(a4)		; all four wheels down G($9910)
	LOOP_FAR _motion_contact_rates,a0
	jsr (a0)
	LOOP_FAR _projection_reset,a0
	jsr (a0)
	LOOP_FAR _motion_position_state,a0
	clr.l (a0)+
	clr.l (a0)+
	clr.l (a0)+
	clr.l (a0)+
	clr.l (a0)
	rts
; D0-D2 = Q4 vector, D3 = unsigned Q16 fraction: D0-D2 scaled
.scale:
	bsr.s .one
	exg d0,d1
	bsr.s .one
	exg d0,d1
	exg d0,d2
	bsr.s .one
	exg d0,d2
	rts
.one:
	move.l d0,d7
	bpl.s .one_positive
	neg.l d7
.one_positive:
	mulu.w d3,d7
	swap d7
	ext.l d7
	tst.l d0
	bpl.s .one_done
	neg.l d7
.one_done:
	move.l d7,d0
	rts

; A2 = state: D0-D2 = heading, pitch and roll of a car pitched LP_THETA
; round the loop and turned LP_PSI about its own vertical axis.
; In the road's frame (along d, up y, across r = the heading's increase):
;   forward f = (cos t cos p, sin t cos p, sin p), up u0 = (-sin t, cos t, 0).
; A heading H0+h and pitch P point f; the roll R brings u0 back:
;   sin R = sin t sin h, cos R = sin t cos h sin P + cos t cos P.
; Of the two (h, P) pointing f, the one with cos P of cos t's sign keeps the
; native pitch continuous over the top.
_loop_angles:
	move.w LP_PSI(a2),d0
	bne.s .turned
	move.w LP_H0(a2),d0
	move.w LP_THETA(a2),d1
	moveq #0,d2
	rts
.turned:
	movem.l d3-d7,-(a7)
	bsr _loop_cos
	move.w d0,d6			; cos p
	move.w LP_PSI(a2),d0
	bsr _loop_sin
	move.w d0,d7			; sin p = f_r
	move.w LP_THETA(a2),d0
	bsr _loop_cos
	move.w d0,d4			; cos t
	move.w LP_THETA(a2),d0
	bsr _loop_sin
	move.w d0,d5			; sin t
	move.w d4,d0
	muls.w d6,d0
	asl.l #2,d0
	swap d0				; f_d
	move.w d5,d3
	muls.w d6,d3
	asl.l #2,d3
	swap d3				; f_y
	muls.w d0,d0
	move.w d7,d1
	muls.w d1,d1
	add.l d1,d0
	bsr _loop_sqrt			; horizontal, Q14
	move.w d0,d1
	move.w d7,d0
	tst.w d4
	bpl.s .upright
	neg.w d0
.upright:
	bsr _loop_asin			; h
	move.w d0,d6
	move.w d3,d0
	move.w #16384,d1
	bsr _loop_asin
	tst.w d4
	bpl.s .pitched
	neg.w d0				; over the top: 180 - P from the same side
	addi.w #720,d0
	tst.w LP_THETA(a2)
	bpl.s .pitched
	subi.w #1440,d0
.pitched:
	move.w d0,d3			; P
	; sin R = sin t sin h
	move.w d6,d0
	bsr _loop_sin
	muls.w d5,d0
	asl.l #2,d0
	swap d0
	move.w d0,d7
	; cos R = sin t cos h sin P + cos t cos P
	move.w d6,d0
	bsr _loop_cos
	muls.w d5,d0
	asl.l #2,d0
	swap d0
	move.w d0,d1
	move.w d3,d0
	move.l d1,-(a7)
	bsr _loop_sin
	move.l (a7)+,d1
	muls.w d0,d1
	asl.l #2,d1
	swap d1
	move.w d3,d0
	move.l d1,-(a7)
	bsr _loop_cos
	move.l (a7)+,d1
	muls.w d4,d0
	asl.l #2,d0
	swap d0
	add.w d1,d0
	move.w d0,d5			; cos R
	move.w d7,d0
	move.w #16384,d1
	bsr _loop_asin
	tst.w d5
	bpl.s .rolled
	neg.w d0
	addi.w #720,d0
	tst.w d7
	bpl.s .rolled
	subi.w #1440,d0
.rolled:
	move.w d0,d2
	move.w d3,d1
	move.w LP_H0(a2),d0
	add.w d6,d0
	bsr _loop_wrap
	movem.l (a7)+,d3-d7
	rts

; A2 = state: moves the car LOOP_LIFT along the road's up axis at
; LP_THETA, (-sin t sin H0, cos t, -sin t cos H0).
_loop_lift:
	move.w LP_THETA(a2),d0
	bsr _loop_sin
	move.w d0,d3
	move.w LP_THETA(a2),d0
	bsr _loop_cos
	muls.w #LOOP_LIFT,d0
	asr.l #7,d0
	asr.l #7,d0
	add.l d0,-$6700(a4)		; Y8
	move.w LP_H0(a2),d0
	bsr _loop_sin
	muls.w d3,d0
	asl.l #2,d0
	swap d0
	muls.w #LOOP_LIFT,d0
	asr.l #7,d0
	asr.l #7,d0
	sub.l d0,-$6704(a4)		; X8
	move.w LP_H0(a2),d0
	bsr _loop_cos
	muls.w d3,d0
	asl.l #2,d0
	swap d0
	muls.w #LOOP_LIFT,d0
	asr.l #7,d0
	asr.l #7,d0
	sub.l d0,-$66fc(a4)		; Z8
	move.l -$6704(a4),d0
	asr.l #3,d0
	move.w d0,-$670a(a4)
	move.l -$6700(a4),d0
	asr.l #3,d0
	move.w d0,-$6708(a4)
	move.l -$66fc(a4),d0
	asr.l #3,d0
	move.w d0,-$6706(a4)
	rts

; A car let go upside down comes down on its roof. The crash keeps the fall,
; and with the wheels up no pass meets the ground again: it fell through the
; road until the replay. Hold a crashed car upside down at the height of its
; last pass in the crash with a wheel on the ground. The crash also keeps the
; speed, and the native motion carries the car along its body: crashed steep,
; it climbed (87 ft at 65 degrees). Beyond 45 degrees a crashed car keeps its
; horizontal direction of travel only (the flight's hold, levelled) and falls
; at 1 g. D0/A0.
_loop_floor:
	lea _loop_floor_y(pc),a0
	tst.b -$69fa(a4)		; crash countdown
	bne.s .crash
	move.l #$80000000,(a0)		; none yet
	rts
.crash:
	move.w -$66b4(a4),d0		; pitch
	bpl.s .positive
	neg.w d0
.positive:
	cmpi.w #180,d0
	ble.s .ground
	LOOP_FAR _flight_held,a0
	move.w #1,(a0)+
	clr.w (a0)+			; _flight_trig: level
	move.w #16384,(a0)
	tst.w -$6bb2(a4)		; pitch cosine: facing back upside down
	bpl.s .level
	neg.w (a0)
.level:
	lea _loop_floor_y(pc),a0
.ground:
	tst.b -$66f0(a4)		; contact mask G($9910)
	beq.s .air
	move.l -$6700(a4),(a0)
	rts
.air:
	cmpi.w #360,d0
	ble.s .out
	move.l (a0),d0
	cmp.l -$6700(a4),d0
	ble.s .out
	move.l d0,-$6700(a4)		; Y8
	asr.l #3,d0
	move.w d0,-$6708(a4)
	clr.w -$66f2(a4)		; fall
.out:
	rts
_loop_floor_y: dc.l $80000000
; D0 = angle: D0 within -720..720
_loop_wrap:
	cmpi.w #720,d0
	ble.s .high
	subi.w #1440,d0
.high:
	cmpi.w #-720,d0
	bge.s .low
	addi.w #1440,d0
.low:
	rts
; D0 = angle: D0 = native sine or cosine, Q14. Preserve D1-D7/A0-A3.
_loop_sin:
	movem.l d1/a0,-(a7)
	move.w d0,-(a7)
	jsr -$7f26(a4)
	addq.w #2,a7
	movem.l (a7)+,d1/a0
	rts
_loop_cos:
	movem.l d1/a0,-(a7)
	move.w d0,-(a7)
	jsr -$7f2c(a4)
	addq.w #2,a7
	movem.l (a7)+,d1/a0
	rts
; D0 = a, D1 = b > 0: D0 = the native asin(a/b), 360 a right angle, 0 when
; b is not positive. Preserve D1-D7/A0-A3.
_loop_asin:
	tst.w d1
	bgt.s .valid
	moveq #0,d0
	rts
.valid:
	movem.l d1-d2/a0-a1,-(a7)
	cmp.w d1,d0
	ble.s .below
	move.w d1,d0
.below:
	move.w d1,d2
	neg.w d2
	cmp.w d2,d0
	bge.s .above
	move.w d2,d0
.above:
	move.w d1,-(a7)
	move.w d0,-(a7)
	LOOP_FAR _code_start,a1
	movea.l (a1),a1
	adda.l #$2b0e,a1
	jsr (a1)
	addq.w #4,a7
	movem.l (a7)+,d1-d2/a0-a1
	rts
; D0 = unsigned long: D0 = its native square root. Preserve D1-D7/A0-A3.
_loop_sqrt:
	movem.l d1-d3/a0-a1,-(a7)
	move.l d0,-(a7)
	LOOP_FAR _code_start,a1
	movea.l (a1),a1
	adda.l #$9564,a1
	jsr (a1)
	addq.w #4,a7
	movem.l (a7)+,d1-d3/a0-a1
	rts
