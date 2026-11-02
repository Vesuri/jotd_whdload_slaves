; Arcade handling's suspension (CUSTOM1=2): the arcade car's pitch on its
; springs ($70D590, ARCADE_ROMS.md). Its body pitches on a front and a rear
; spring and damper, 5 ft either side of the centre of gravity: N = k x + c x'
; for compression x, the damper doubled while compressing, the load doubled
; past 1.5 ft of compression (the bump stop), none with the wheel off the
; ground and at most the car's weight. The tyre forces act 1.567 ft below the
; centre of gravity, so braking and driving pitch the car, and the spring
; loads are the tyres' loads. There is no roll dynamics: the arcade sets roll
; from the wheel contact, as the native contact code does.
;
; The native contact pass ($CAB6) snaps the car to the ground instead: it
; pushes it out along its normal by the wheels' average depth and turns its
; pitch to the wheels' height difference. Here, on its ground branch (three
; wheels down or a diagonal pair), the body's pitch is that ground pitch
; (the native wheel heights' difference, the four corner points 90 units
; apart) plus the springs' own displacement, which they step for each field
; from their forces, within a travel stop; the displacement turns the car
; for the coming pass. The ground does not move the springs: the native
; wheel heights are whole units (0.18 ft, 540 lb on a spring), and with the
; height native (too coarse for the springs' heave) a ramp's foot or a nose
; down landing left an axle in the air while the native contact had it
; down, and the rear came loose. So the native push keeps the car on the
; ground and the native landing test judges a touchdown. The native motion moves the
; car along its body, so the springs' pitch against the ground would climb
; it off the ground (or into it): that part of the motion is taken back, and
; what is left (the native heights' rounding) falls back under gravity, as
; the native push only lifts. With fewer wheels down the native pair contact
; turns the car (on a jump's lip, the take-off rotation) and the native
; flight carries on: the pitch velocity becomes the native pitch rate, and
; comes back on the ground branch. The crash, the loop and the model's
; resets stand it down.
; See ARCADE_HANDLING_PLAN.md, H3 round 11.

SU_VALID equ 0		; w: nonzero while the springs hold the car
SU_P equ 2		; l: pitch velocity at the axles (5 ft x rate), nose up, Q22 ft/s
SU_EF equ 6		; l: front axle's clearance, Q22 ft
SU_ER equ 10		; l: rear axle's
SU_PP equ 14		; l: this pass's pitch displacement at the axles, Q22 ft
SU_FX equ 18		; w: the tyres' longitudinal force, lb
SU_NF equ 20		; w: front load, lb, the last pass's average
SU_NR equ 22		; w: rear load, lb
SU_PITCH equ 24		; l+w: pitch not yet applied, Q16, and the angle it was for
SU_YREM equ 30		; w: height not yet applied, Q8 long units
SU_W equ 32		; l: fall velocity while above the ground, up, Q22 ft/s
SU_REL equ 36		; w: sine of the body's pitch against the ground, Q14
SU_GD equ 38		; l: the ground's pitch as the axles' displacement, Q22 ft
SU_D equ 42		; l: the springs' displacement at the front axle, Q22 ft
SU_GE equ 46		; l: this pass's estimate of the ground's pitch, Q22 ft
SU_GS equ 50		; w: the direction the ground's pitch last moved, +-1, 0 held
SU_SIZE equ 52

SUSP_KF equ 3000	; springs, lb/ft
SUSP_KR equ 3500
SUSP_CF equ 400		; dampers, lb s/ft
SUSP_CR equ 500
SUSP_W equ 3525		; weight, lb: the load limit
SUSP_K_PX equ 321	; lb at 1.567 ft -> Q22 ft/s at the axles per field: 5 h dt / I
			; (axle loads: 25 dt / I = 1024 per lb, a shift by 10)
SUSP_BUMP equ 24576	; bump stop, 1.5 ft of compression in Q14
SUSP_LF equ 3215414	; unloaded clearance, Q22 ft: the static sag (1762.5 lb
SUSP_LR equ 2863495	; on the spring) plus a ride height of 1 unit
SUSP_V_MAX equ 268435456	; 64 ft/s, Q22
SUSP_STEPS equ 50	; fields one pass steps at most, as the model
SUSP_RIDE equ 751232	; ride height, 1 unit in Q22 ft
SUSP_G equ 2634478	; gravity, Q22 ft/s per field (32.17 x 5 / 256)
SUSP_GD_BAND equ 232810	; the ground's pitch is held within this, Q22 ft at
			; the axles: a whole unit on both wheels of a pair
			; (0.0555 ft, 0.64 degrees)
SUSP_PITCH_HOLD equ 68631	; the pitch word is kept within 3/4 of a quarter
			; degree of the body's pitch (Q22 ft at the axles)
SUSP_D_MAX equ 1258291	; travel stop: 0.3 ft at the axles (3.4 degrees), so
			; each axle keeps 0.2 ft of its static compression
			; (0.5 ft rear); 0.7 g of braking takes 0.12 ft

	cnop 0,4
_suspension_state: dcb.b SU_SIZE,0

; The rest of the slave is out of PC-relative reach: \2 = address of \1.
SUSP_FAR macro
	lea _suspension_state(pc),\2
	adda.l #\1-_suspension_state,\2
	endm

; Replaces CMPI.B #3,-2(A5) at $CB52 of the native contact pass, after the
; contact mask (-1(A5)) and the wheel heights G($947E..$9484) are known; the
; flags are the displaced instruction's. Preserves all registers.
_suspension_contact:
	movem.l d0-d7/a0-a3,-(a7)
	lea _suspension_state(pc),a2
	SUSP_FAR _contact_arcade,a0
	tst.w (a0)
	beq .done
	tst.b -$69fa(a4)		; crash countdown
	bne .drop
	lea _loop_state(pc),a0
	tst.w LP_ACTIVE(a0)
	bne .drop
	; only on the ground branch (three wheels or a diagonal pair, as the
	; native pass): with fewer, the native rear- or front-pair contact
	; turns the car, the take-off rotation on a jump's lip
	cmpi.b #3,-2(a5)		; wheels down
	bhs.s .ground
	cmpi.b #9,-1(a5)
	beq.s .ground
	cmpi.b #6,-1(a5)
	bne .air
.ground:
	tst.w SU_VALID(a2)
	bne.s .held
	bsr _suspension_touch
.held:
	bsr _suspension_measure
	SUSP_FAR _time_scalar_fields,a0
	move.w (a0),d7
	beq.s .owned
	cmpi.w #SUSP_STEPS,d7
	bls.s .steps
	moveq #SUSP_STEPS,d7
.steps:
	bsr _suspension_steps
	bsr _suspension_apply
.owned:
	moveq #1,d0
	bra.s .own
.air:
	tst.w SU_VALID(a2)
	beq.s .drop
	bsr _suspension_release
.drop:
	moveq #0,d0
	move.w d0,SU_VALID(a2)
.own:
	SUSP_FAR _suspension_own,a0
	move.w d0,(a0)
.done:
	movem.l (a7)+,d0-d7/a0-a3
	cmpi.b #3,-2(a5)
	rts

; Replaces TST.W -4(A5) / BEQ.S $CBBC at $CB94, the ground pass's pitch snap,
; while the springs hold the car: on to the push out of the ground at $CBBC
; (the native path for level wheels).
_suspension_ground:
	move.l a0,-(a7)
	SUSP_FAR _suspension_own,a0
	tst.w (a0)
	movea.l (a7)+,a0
	bne.s .level
	tst.w -4(a5)
	bne.s .pitch
.level:
	addi.l #$cbbc-$cb9a,(a7)
.pitch:
	rts

; A2 = state. The first pass on the ground branch: the springs start at
; rest, the body on the ground's pitch. The native pitch rate is the body turning on a wheel pair or in
; the air, not the springs' velocity; taken as that, its damper force took
; an axle's whole load for the pass (a loose rear at a ramp's foot), as the
; native snap never did. Clobbers D0-D1/A0-A1/A3.
_suspension_touch:
	clr.l SU_P(a2)
	clr.l SU_D(a2)
	clr.l SU_PP(a2)
	SUSP_FAR _contact_rates+8,a0
	lea -$66ea(a4),a1		; pitch rate G($9916)
	moveq #0,d1
	SUSP_FAR _contact_write_rate,a3
	jsr (a3)
	clr.l SU_PITCH(a2)
	move.w -$66b4(a4),SU_PITCH+4(a2)
	clr.w SU_YREM(a2)
	clr.l SU_W(a2)
	clr.w SU_REL(a2)
	move.w #1,SU_VALID(a2)		; 1: the ground's pitch not yet taken
	rts

; A2 = state. The last pass with a wheel down is over: the pitch velocity
; becomes the pitch rate, for the native flight. Clobbers D0-D1/A0-A1/A3.
_suspension_release:
	move.l SU_P(a2),d0
	moveq #10,d1
	asr.l d1,d0			; Q12 ft/s
	bsr _suspension_word
	muls.w #115,d0			; -> Q16 quarter degrees per native step
	move.l d0,d1
	SUSP_FAR _contact_rates+8,a0
	lea -$66ea(a4),a1
	SUSP_FAR _contact_write_rate,a3
	jsr (a3)
	clr.w SU_NF(a2)
	clr.w SU_NR(a2)
	rts

; D0.L clamped to a signed word.
_suspension_word:
	cmpi.l #32767,d0
	ble.s .high
	move.l #32767,d0
.high:
	cmpi.l #-32768,d0
	bge.s .low
	move.l #-32768,d0
.low:
	rts

; A2 = state. The axles' clearances: the ride height and the body's pitch
; against the ground, from the native wheel heights' difference, wheels 0-1
; the front pair 45 units ahead, 2-3 the rear, interpolated to the arcade's
; axles 5 ft (27.9 units) either side. Also the tyres' force. Clobbers
; D0-D3/A0.
_suspension_measure:
	lea -$6b82(a4),a0		; G($947E)
	moveq #3,d3
	moveq #0,d1
.wheel:
	move.w (a0)+,d0
	cmpi.w #1000,d0
	ble.s .wheel_high
	move.w #1000,d0
.wheel_high:
	cmpi.w #-1000,d0
	bge.s .wheel_low
	move.w #-1000,d0
.wheel_low:
	cmpi.w #2,d3
	blt.s .rear
	add.w d0,d1
	bra.s .next
.rear:
	sub.w d0,d1
.next:
	dbf d3,.wheel
	muls.w #20329,d1		; front less rear sum, units: half the pairs'
	moveq #14,d2			; difference x 4 is twice it in Q3 units,
	asr.l d2,d1			; x 5 ft / 8.06 ft
	; the ground's pitch: the body's (5 ft x the pitch word) less that,
	; what the native pass would snap the pitch to
	move.w d1,d0
	bsr .feet
	move.l d0,d2
	move.w -$66b4(a4),d0		; pitch G($994C)
	muls.w #22877,d0		; x 5 ft x pi / 720 / 4, Q22 ft
	asl.l #2,d0
	sub.l d2,d0
	; held while within the wheel heights' rounding of it: taken every
	; pass, the rounding of a pitch that the springs' displacement had
	; moved went back into the next pass's pitch, which then climbed by
	; the displacement's part of a step each pass and dropped by a step,
	; a 1 degree shake at 5 Hz under power or braking
	; beyond it, up to twice the band, the ground's pitch moves to the
	; band's edge: moved further, a quarter degree of pitch moved the
	; wheel heights' rounding by a unit and the estimate back past the
	; band, a pitch that alternated by a quarter degree each field.
	; Further out it is taken whole (a ramp's foot, a lip), unless that
	; reverses the last pass's move: where the ground's slope changes the
	; estimate moved by up to twice the body's pitch, and taken whole it
	; swung back each pass, a pitch alternating by 1-1.5 degrees on hills
	move.l d0,SU_GE(a2)
	cmpi.w #1,SU_VALID(a2)
	beq.s .ground_new
	sub.l SU_GD(a2),d0
	moveq #1,d2			; the direction
	move.l d0,d1
	bpl.s .ground_abs
	neg.l d1
	moveq #-1,d2
.ground_abs:
	subi.l #SUSP_GD_BAND,d1
	bgt.s .ground_out
	clr.w SU_GS(a2)
	bra.s .ground_held
.ground_out:
	cmpi.l #SUSP_GD_BAND,d1
	ble.s .ground_edge
	move.w SU_GS(a2),d3
	add.w d2,d3
	bne.s .ground_whole		; not a reversal
.ground_edge:
	tst.w d2
	bpl.s .ground_move
	neg.l d1
.ground_move:
	add.l d1,SU_GD(a2)
	move.w d2,SU_GS(a2)
	bra.s .ground_held
.ground_whole:
	add.l d0,SU_GD(a2)
	move.w d2,SU_GS(a2)
	bra.s .ground_held
.ground_new:
	move.l d0,SU_GD(a2)
	clr.w SU_GS(a2)
	move.w #2,SU_VALID(a2)
.ground_held:
	; the springs' displacement is their own state, moved only by their
	; forces: the native wheel heights are whole units, and with the
	; height native a ramp's foot or a landing would put the rear axle in
	; the air while the native contact has it down
	move.l SU_D(a2),d0
	add.l SU_PP(a2),d0
	clr.l SU_PP(a2)
	; the travel stop: a pitch rate further out stops
	cmpi.l #SUSP_D_MAX,d0
	bgt.s .stop_up
	cmpi.l #-SUSP_D_MAX,d0
	bge.s .travel
	move.l #-SUSP_D_MAX,d0
	tst.l SU_P(a2)
	bpl.s .travel
	clr.l SU_P(a2)
	bra.s .travel
.stop_up:
	move.l #SUSP_D_MAX,d0
	tst.l SU_P(a2)
	bmi.s .travel
	clr.l SU_P(a2)
.travel:
	move.l d0,SU_D(a2)
	; the body's pitch: the ground's and the displacement (the pass's
	; steps add theirs in _suspension_apply)
	; to the nearest quarter degree, kept while within SUSP_PITCH_HOLD of
	; it: the springs' small motions flipped it by a quarter degree
	move.l d0,d1
	add.l SU_GD(a2),d1
	move.w -$66b4(a4),d2
	muls.w #22877,d2
	asl.l #2,d2
	sub.l d1,d2
	bpl.s .pitch_abs
	neg.l d2
.pitch_abs:
	cmpi.l #SUSP_PITCH_HOLD,d2
	blt.s .pitch_kept
	asr.l #2,d1
	bmi.s .pitch_neg
	addi.l #11438,d1
	bra.s .pitch_round
.pitch_neg:
	subi.l #11438,d1
.pitch_round:
	divs.w #22877,d1
	move.w d1,-$66b4(a4)
.pitch_kept:
	clr.l SU_PITCH(a2)
	move.w -$66b4(a4),SU_PITCH+4(a2)
	move.l d0,d1
	addi.l #SUSP_RIDE,d0
	move.l d0,SU_EF(a2)
	move.l #SUSP_RIDE,d0
	sub.l d1,d0
	move.l d0,SU_ER(a2)
	lea _handling_state(pc),a0
	move.w HS_FXIN(a0),SU_FX(a2)
	rts
; D0.W Q3 units -> D0.L Q22 ft (x 0.1791 / 8 x 2^22 = 93904). Preserves D1.
.feet:
	move.l d1,-(a7)
	move.w d0,d1
	muls.w #28368,d1
	ext.l d0
	swap d0
	clr.w d0
	add.l d1,d0
	move.l (a7)+,d1
	rts

; A2 = state, D7 = fields (1..SUSP_STEPS). The springs and the body for
; each field, explicit for the loads and with the new velocity for the
; displacement, as the arcade's step. Clobbers D0-D7/A0.
_suspension_steps:
	clr.l SU_PP(a2)
	move.w d7,-(a7)			; the fields, and the loads' sums: the
	clr.l -(a7)			; tyres get the pass's average, not its
	clr.l -(a7)			; last field's (a rebound's moment off)
	subq.w #1,d7
.field:
	; front: compression and its velocity
	move.l SU_EF(a2),d0
	add.l SU_PP(a2),d0
	move.l #SUSP_LF,d1
	sub.l d0,d1
	move.l SU_P(a2),d2
	neg.l d2
	move.w #SUSP_KF,d3
	move.w #SUSP_CF,d4
	bsr _suspension_spring
	move.w d0,d5			; front load
	; rear
	move.l SU_ER(a2),d0
	sub.l SU_PP(a2),d0
	move.l #SUSP_LR,d1
	sub.l d0,d1
	move.l SU_P(a2),d2
	move.w #SUSP_KR,d3
	move.w #SUSP_CR,d4
	bsr _suspension_spring
	move.w d0,d6			; rear load
	moveq #0,d0
	move.w d5,d0
	add.l d0,(a7)
	move.w d6,d0
	add.l d0,4(a7)
	; pitch: the loads' moment and the tyres' force below the centre of
	; gravity (braking pitches the nose down)
	move.w d5,d0
	sub.w d6,d0
	ext.l d0
	moveq #10,d1
	asl.l d1,d0
	move.w SU_FX(a2),d1
	muls.w #SUSP_K_PX,d1
	add.l d1,d0
	add.l SU_P(a2),d0
	move.l #SUSP_V_MAX,d1
	bsr _suspension_limit
	move.l d0,SU_P(a2)
	; displacement: v dt = v x 5 / 256
	move.l d0,d1
	asl.l #2,d0
	add.l d1,d0
	asr.l #8,d0
	add.l d0,SU_PP(a2)
	dbf d7,.field
	move.l (a7)+,d0
	move.l (a7)+,d1
	move.w (a7)+,d2
	divu.w d2,d0
	divu.w d2,d1
	move.w d0,SU_NF(a2)
	move.w d1,SU_NR(a2)
	rts

; D0.L limited to +-D1.L.
_suspension_limit:
	cmp.l d1,d0
	ble.s .high
	move.l d1,d0
.high:
	neg.l d1
	cmp.l d1,d0
	bge.s .low
	move.l d1,d0
.low:
	rts

; D1.L compression Q22 ft, D2.L its velocity Q22 ft/s, D3.W spring lb/ft,
; D4.W damper lb s/ft. Returns D0.W the load, lb. Clobbers D1-D2/D4.
_suspension_spring:
	moveq #0,d0
	tst.l d1
	ble.s .done
	asr.l #8,d1			; Q14 ft
	cmpi.l #32767,d1
	ble.s .deep
	move.l #32767,d1
.deep:
	move.w d1,d0
	muls.w d3,d0
	move.l d1,-(a7)
	moveq #14,d1
	asr.l d1,d0
	asr.l d1,d2			; Q8 ft/s
	move.l d0,d1
	move.l d2,d0
	bsr _suspension_word
	tst.w d0
	ble.s .damp
	add.w d4,d4			; doubled while compressing
.damp:
	muls.w d4,d0
	asr.l #8,d0
	add.l d1,d0
	move.l (a7)+,d1
	cmpi.w #SUSP_BUMP,d1
	ble.s .stop
	add.l d0,d0
.stop:
	tst.l d0
	bpl.s .positive
	moveq #0,d0
.positive:
	cmpi.l #SUSP_W,d0
	ble.s .done
	move.l #SUSP_W,d0
.done:
	rts

; A2 = state, A5 = the native pass's frame. This pass's displacement turns
; the car about its roll axis, as the native pitch helper ($B194), and its
; height follows the ground. Clobbers D0-D4/A0-A1/A3.
_suspension_apply:
	; the axles' displacement over 5 ft, Q16 quarter degrees
	move.l SU_PP(a2),d0
	move.w #23469,d1		; x 229.18 / 5 / 64, Q15
	bsr _suspension_mulq15
	move.w -$6bae(a4),d1		; x cos roll, Q14
	SUSP_FAR _contact_project_q16,a3
	jsr (a3)
	lea SU_PITCH(a2),a0
	lea -$66b4(a4),a1		; pitch G($994C)
	SUSP_FAR _contact_add_angle,a3
	jsr (a3)
	; the native motion's rise along the pitch against the ground over the
	; pass's fields, taken back: u n dt (pitch against the ground at the
	; axles) / 5 ft, the pitch word less this pass's estimate of the
	; ground: the springs' displacement, the held ground pitch's error (up
	; to SUSP_GD_BAND) and the word's rounding. With the displacement
	; alone the car climbed off the road or sank into it, which the native
	; push undid by a whole unit, a saw-tooth in the height. (The pitch
	; the pass's motion had, before the measure, less the estimate lifted
	; the whole car at a ramp's foot: the rear axle came off the ground.)
	SUSP_FAR _time_scalar_fields,a0
	move.w (a0),d3
	cmpi.w #SUSP_STEPS,d3
	bls.s .fields
	moveq #SUSP_STEPS,d3
.fields:
	move.l SU_EF(a2),d0
	subi.l #SUSP_RIDE,d0
	add.l SU_PP(a2),d0
	asr.l #8,d0			; Q14 ft
	bsr _suspension_word
	move.w d0,d1			; / 5 ft: the pitch's sine for the
	muls.w #13107,d1		; handling's slope force
	swap d1
	move.w d1,SU_REL(a2)
	move.w -$66b4(a4),d0
	muls.w #22877,d0
	asl.l #2,d0
	sub.l SU_GE(a2),d0
	asr.l #8,d0			; Q14 ft
	bsr _suspension_word
	lea _handling_state(pc),a0
	muls.w HS_U(a0),d0		; Q20 ft x ft/s
	asr.l #8,d0			; / 256: dt / 5 ft = 1 / 256
	move.w d3,d1
	bsr _suspension_mulw		; Q20 ft
	asr.l #6,d0			; Q14 ft
	neg.l d0
	move.l d0,-(a7)
	; above the ground (the wheels' average height -8(A5) of the native
	; pass), the car falls under gravity, to the ground at most
	moveq #0,d0
	move.w -8(a5),d1
	ble.s .grounded
	move.l SU_W(a2),d2
	subq.w #1,d3
.fall:
	subi.l #SUSP_G,d2
	move.l d2,d4
	asl.l #2,d4
	add.l d2,d4
	asr.l #8,d4			; v dt = v x 5 / 256
	add.l d4,d0
	dbf d3,.fall
	move.l d2,SU_W(a2)
	asr.l #8,d0			; Q14 ft
	muls.w #2934,d1			; the height, Q14 ft
	neg.l d1
	cmp.l d1,d0
	bge.s .falling
	move.l d1,d0
.grounded:
	clr.l SU_W(a2)
.falling:
	add.l (a7)+,d0
	bsr _suspension_word
	muls.w #22873,d0		; x 44.67 long units per ft
	moveq #15,d1
	asr.l d1,d0			; Q8 long units
	add.w SU_YREM(a2),d0
	ext.l d0
	move.l d0,d1
	asr.l #8,d0
	andi.w #255,d1
	move.w d1,SU_YREM(a2)
	add.l d0,-$6700(a4)		; Y long G($9900)
	move.l -$6700(a4),d0
	asr.l #3,d0
	move.w d0,-$6708(a4)		; Y word G($98F8)
	rts

; D0.L signed x D1.W unsigned -> D0.L, the low 32 bits. Clobbers D1-D2.
_suspension_mulw:
	move.l d0,d2
	swap d0
	muls.w d1,d0			; high word, signed
	swap d0
	clr.w d0
	mulu.w d1,d2			; low word, unsigned
	add.l d2,d0
	rts

; D0.L signed x D1.W positive Q15 -> D0.L, rounded down. Clobbers D1-D2.
_suspension_mulq15:
	move.l d0,d2
	swap d0
	muls.w d1,d0			; high word, signed
	add.l d0,d0
	andi.l #$ffff,d2
	mulu.w d1,d2			; low word, unsigned
	moveq #15,d1
	lsr.l d1,d2
	add.l d2,d0
	rts
