; Arcade handling, CUSTOM1=2: a two-wheel car model replaces the native
; steering and skid. It steps once per PAL field (dt 1/50 s); a frame that
; took n fields runs n steps, each with its own field's mouse X. The native
; engine drives the forward speed; the model turns the car, adds its
; sideways motion and feeds its own forward speed change (tyre drag, slides,
; v r) back to the native speed. Every hook is installed only for CUSTOM1=2,
; so the other settings run exactly the release code.

	IFND VERIFY_DRIVETRAIN_PHASE
	FAIL "VERIFY_HANDLING requires VERIFY_DRIVETRAIN_PHASE"
	ENDC

HANDLING_CAP equ 50		; steps a frame may catch up, 1 s
HANDLING_RING equ 64		; mouse samples kept, a power of two
HANDLING_V8_MAX equ 4160	; velocity eighths the model accepts, 145 MPH
HANDLING_JUMP equ 40		; eighths per field: a faster change is a reset
HANDLING_K_FX equ 295		; lb per eighth of velocity gained per field
HANDLING_FX_DRIVE equ 2115	; drive force limit, lb (0.6 g)
HANDLING_FX_BRAKE equ 2470	; front brake limit, lb (0.7 g)
HANDLING_FX_COAST equ 705	; engine braking limit, lb (0.2 g)
HANDLING_K_LAT equ 457		; Q6 ft/s -> Q16 long position units per field
HANDLING_K_STEP equ 3653	; Q6 ft/s -> Q16 long position units per native step
HANDLING_U_SCREECH equ 1730	; Q6 ft/s, 18 MPH: slower tyres do not screech
HANDLING_K_PH equ 2435		; Q22 ft/s -> Q16 native velocity, after >> 16

; Model constants for one field, from tmp/arcade/tools/handling_fx.py.
; Speeds are Q6 ft/s words, the yaw rate and tyre deflection Q11 words
; (their states Q22 and Q27 longs), loads Q2 lb, forces lb, angles and
; curve terms Q14, the heading a Q16 long in G($994A) units.
HM_K_DT_M equ 748		; lb -> Q22 ft/s
HM_K_DT_I equ 6554		; lb at 5 ft -> Q27 rad/s
HM_K_PSI equ 143		; Q11 rad/s -> Q16 heading
HM_K_DN equ 10269		; lb -> Q16 lb of load transfer
HM_K_ROLL equ 30025		; share of a torque that reaches the road, Q15
HM_K_UNROLL equ 17881		; its inverse, Q14
HM_K_Y equ 16448		; lb -> Q27 ft of tyre deflection
HM_K_DELTA equ 32029		; mouse count -> Q14 rad, after >> 10
HM_K_U equ 27559		; velocity eighth -> Q6 ft/s, after >> 13
HM_K equ 8160			; tyre lateral spring, lb/ft
HM_N0 equ 7050			; static axle load, Q2 lb
HM_FX_MAX equ 8000		; longitudinal force input limit, lb
HM_R_MAX equ 1610612736		; 12 rad/s, Q27
HM_V_MAX equ 1073741824		; 256 ft/s, Q22
HM_Y_MAX equ 536870912		; 4 ft, Q27
HM_SLIP_MAX equ 8192		; 128 ft/s, Q6

; Axle state
AX_Y equ 0			; tyre deflection, Q27 ft
AX_W equ 4			; wheel speed while sliding, Q22 ft/s
AX_SLIDE equ 8			; nonzero while the wheel slides
AX_PEAK equ 9			; set by a step past the curve's peak, or sliding
AX_SIZE equ 10

; Model state, inputs and step temporaries
HS_V equ 0			; lateral velocity, Q22 ft/s
HS_R equ 4			; yaw rate, Q27 rad/s
HS_DN equ 8			; load moved to the rear, Q16 lb
HS_PSI equ 12			; heading, Q16, wrapped to +-720
HS_FRONT equ 16
HS_REAR equ HS_FRONT+AX_SIZE
HS_U equ 36			; input: forward speed, Q6 ft/s
HS_COUNTS equ 38		; input: mouse X - 320
HS_FXIN equ 40			; input: tyres' longitudinal force, lb
HS_BRAKE equ 42			; input: front brake torque, lb ft, <= 0
HS_CONTACT equ 44		; input: bit 0 front, bit 1 rear axle on the ground
HS_FYSUM equ 46			; output: lateral tyre forces, lb
HS_NF equ 48
HS_NR equ 50
HS_SD equ 52
HS_CD equ 54
HS_RW equ 56
HS_VCR equ 58
HS_FX equ 60
HS_FYBF equ 62
HS_FYR equ 64
HS_DUF equ 66			; output: forward speed the step adds beyond fx, Q22
HS_FXBF equ 70
HS_MODEL equ 72			; size of the part the step uses
; Game coupling
HS_HEAD equ 72			; heading not yet applied, Q16
HS_DX equ 76			; sideways motion not yet applied, Q8 long units
HS_DZ equ 80
HS_INDEX equ 84			; next mouse sample, in TS_FIELDS counts
HS_PASS equ 88			; TS_PASSES of the last steering call
HS_SKIP equ 92			; steps this frame leaves out (catch-up cap)
HS_V8 equ 94			; velocity eighths after the last steering call
HS_NPREV equ 96			; fields the last steering call stepped
HS_LAST_HEAD equ 98		; G($994A) after the last steering call
HS_LOOP equ 100			; fields left in this call
HS_SKID equ 102			; tyres screeched in this frame
HS_PHASE equ 103		; the speed came from the phase solver
HS_UBASE equ 104		; native forward speed of this call, Q6 ft/s
HS_DU equ 106			; forward speed the model added in this call, Q22
HS_CARRY equ 110		; native speed not yet applied, Q16 velocity
HS_SIZE equ 114

; The slave's globals and Time.s lie beyond PC-relative range from this
; module: reach them from a local base with assembler-constant offsets.
_handling_install:
	IFD VERIFY_HANDLING_MATH
	bsr _handling_math_test
	ENDC
	movem.l d0/a0-a3,-(a7)
	lea _handling_install(pc),a3
	movea.l a3,a0
	adda.l #_ct_ct1-_handling_install,a0
	move.l (a0),d0
	cmpi.l #2,d0
	bne .done
	movea.l a3,a0
	adda.l #_time_state-_handling_install,a0
	lea _handling_time(pc),a1
	move.l a0,(a1)
	movea.l a3,a0
	adda.l #_time_vbl-_handling_install,a0
	lea _handling_time_vbl(pc),a1
	move.l a0,(a1)
	movea.l a3,a0
	adda.l #_time_scalar_fields-_handling_install,a0
	lea _handling_fields(pc),a1
	move.l a0,(a1)
	movea.l a3,a0
	adda.l #_motion_yaw_rate-_handling_install,a0
	lea _handling_yaw_rate(pc),a1
	move.l a0,(a1)
	movea.l a3,a0
	adda.l #_motion_state-_handling_install,a0
	lea _handling_motion(pc),a1
	move.l a0,(a1)
	movea.l a3,a0
	adda.l #_code_start-_handling_install,a0
	move.l (a0),d0
	addi.l #$b44e,d0
	lea _handling_tail(pc),a1
	move.l d0,(a1)
	movea.l a3,a0
	adda.l #_resload-_handling_install,a0
	movea.l (a0),a2
	movea.l a3,a0
	adda.l #_code_start-_handling_install,a0
	movea.l (a0),a1
	lea _handling_patches(pc),a0
	jsr resload_Patch(a2)
	; Three slave sites: steering, the neutral-steering shortcut and the
	; published movement vector. Each replaces two 4-byte instructions.
	lea _phase_steering_site(pc),a1
	lea _handling_steer(pc),a0
	move.w #$4ef9,(a1)+		; JMP
	move.l a0,(a1)+
	move.w #$4e71,(a1)
	lea _phase_neutral_site(pc),a1
	lea _handling_neutral(pc),a0
	move.w #$4eb9,(a1)+		; JSR
	move.l a0,(a1)+
	move.w #$4e71,(a1)
	lea _phase_vector_site(pc),a1
	lea _handling_vector(pc),a0
	move.w #$4eb9,(a1)+
	move.l a0,(a1)+
	move.w #$4e71,(a1)
	jsr resload_FlushCache(a2)
.done:
	movem.l (a7)+,d0/a0-a3
	rts
_handling_patches:
	PL_START
	; PERF_RANGE VERIFY_HANDLING $00050 $0006: per-field mouse samples
	PL_PS $50,_handling_vbl
	; PERF_RANGE VERIFY_HANDLING $08a1a $0006: replay records the model's screech
	PL_PS $8a1a,_handling_replay_skid
	; PERF_RANGE VERIFY_HANDLING $0b61a $0006: the model's screech
	PL_PS $b61a,_handling_skid_sound
	PL_END
_handling_tail: dc.l 0		; native angle and trig tail, B44E
_handling_time: dc.l 0		; _time_state
_handling_time_vbl: dc.l 0	; _time_vbl
_handling_fields: dc.l 0	; _time_scalar_fields
_handling_yaw_rate: dc.l 0	; _motion_yaw_rate
_handling_motion: dc.l 0	; _motion_state

; Replaces _time_vbl at $50. The sample of field k is X after its VBL, so
; ring[TS_FIELDS] is written by the next VBL, before the native mouse update.
_handling_vbl:
	movea.l (a1),a4
	move.w sr,-(a7)
	movem.l d0/a0,-(a7)
	movea.l _handling_time(pc),a0
	move.w TS_FIELDS+2(a0),d0
	andi.w #HANDLING_RING-1,d0
	add.w d0,d0
	lea _handling_ring(pc),a0
	move.w -$6a06(a4),(a0,d0.w)
	movem.l (a7)+,d0/a0
	move.w (a7)+,ccr
	move.l _handling_time_vbl(pc),-(a7)
	rts

; Native B3FC/B428 never start a skid now, so the flag the replay records
; ($8A1A) and the skid sound ($B61A) follow the model's tyres instead.
_handling_replay_skid:
	tst.b -$50cf(a4)
	bne.s .skid
	move.l a0,-(a7)
	lea _handling_state(pc),a0
	tst.b HS_SKID(a0)
	movea.l (a7)+,a0
	bne.s .skid
	addi.l #$8a28-$8a20,(a7)
.skid:
	rts
_handling_skid_sound:
	tst.b -$50cf(a4)
	bne.s .native
	addi.l #$b65e-$b620,(a7)
	lea _handling_state(pc),a0
	tst.b HS_SKID(a0)
	beq.s .native
	bsr _audio_skid
.native:
	rts

; Phase solver: always take the steering call, the model turns the car
; even with the mouse centred. Makes CMPI #38 / BHI take the branch.
_handling_neutral:
	moveq #-1,d0
	rts

; _phase_published: add the model's sideways velocity to the published
; movement vector, which crash drift and barrier bounces reuse.
_handling_vector:
	lea _handling_state(pc),a0
	move.w HS_V(a0),d0
	muls.w #HANDLING_K_STEP,d0
	swap d0
	move.w d0,d1
	muls.w -$6bb6(a4),d0
	add.l d0,d0
	add.l d0,d0
	swap d0
	add.w d0,-$66e2(a4)
	muls.w -$6bb8(a4),d1
	add.l d1,d1
	add.l d1,d1
	swap d1
	sub.w d1,-$66de(a4)
	lea _drivetrain_state(pc),a0
	clr.w 6(a0)
	rts

; Entered by JMP from _phase_steering_continue, after its turn-flag CLR,
; inside the native steering frame (A5). Steps the model for each field of
; _time_scalar_fields, applies its heading and sideways motion and goes on
; to the native angle and trig tail at B44E. D0/D1/A0/A1 are scratch.
_handling_steer:
	movem.l d2-d7/a2-a3,-(a7)
	lea _handling_state(pc),a0
	bsr _handling_sync
	movea.l _handling_fields(pc),a1
	move.w (a1),HS_LOOP(a0)
	beq .applied
.field:
	move.l HS_INDEX(a0),d0
	addq.l #1,HS_INDEX(a0)
	tst.w HS_SKIP(a0)
	beq.s .sample
	subq.w #1,HS_SKIP(a0)
	bra .next
.sample:
	movea.l _handling_time(pc),a1
	move.l TS_FIELDS(a1),d1
	sub.l d0,d1
	bgt.s .ring
	move.w -$6a06(a4),d1
	bra.s .mouse
.ring:
	andi.w #HANDLING_RING-1,d0
	add.w d0,d0
	lea _handling_ring(pc),a1
	move.w (a1,d0.w),d1
.mouse:
	subi.w #320,d1
	move.w d1,HS_COUNTS(a0)
	; sideways motion from the velocity before the step, as for the heading
	move.w HS_V(a0),d0
	muls.w #HANDLING_K_LAT,d0
	asr.l #8,d0
	move.w d0,d1
	moveq #14,d2
	muls.w -$6bb6(a4),d0
	asr.l d2,d0
	add.l d0,HS_DX(a0)
	muls.w -$6bb8(a4),d1
	asr.l d2,d1
	sub.l d1,HS_DZ(a0)
	; the native speed plus what the model has added in this call; the
	; speed stops at zero rather than changing sign
	move.l HS_DU(a0),d0
	swap d0
	add.w HS_UBASE(a0),d0
	move.w HS_UBASE(a0),d1
	eor.w d0,d1
	bpl.s .u_sign
	moveq #0,d0
.u_sign:
	move.w d0,HS_U(a0)
	move.l HS_PSI(a0),-(a7)
	bsr _handling_step
	move.l HS_DUF(a0),d0
	add.l HS_DU(a0),d0
	cmpi.l #HM_V_MAX,d0
	ble.s .du_high
	move.l #HM_V_MAX,d0
.du_high:
	cmpi.l #-HM_V_MAX,d0
	bge.s .du_low
	move.l #-HM_V_MAX,d0
.du_low:
	move.l d0,HS_DU(a0)
	move.l HS_PSI(a0),d0
	sub.l (a7)+,d0
	cmpi.l #720<<16,d0
	ble.s .turn_high
	subi.l #1440<<16,d0
.turn_high:
	cmpi.l #-720<<16,d0
	bge.s .turn_low
	addi.l #1440<<16,d0
.turn_low:
	add.l d0,HS_HEAD(a0)
	move.b HS_FRONT+AX_PEAK(a0),d0
	or.b HS_REAR+AX_PEAK(a0),d0
	beq.s .next
	cmpi.w #HANDLING_U_SCREECH,HS_U(a0)
	ble.s .next
	st HS_SKID(a0)
.next:
	subq.w #1,HS_LOOP(a0)
	bne .field
	bsr _handling_feedback
.applied:
	move.w HS_HEAD(a0),d0
	beq.s .turned
	clr.w HS_HEAD(a0)
	bsr _handling_turn
	lea _handling_state(pc),a0
.turned:
	move.l HS_DX(a0),d0
	asr.l #8,d0
	add.l d0,-$6704(a4)
	andi.l #255,HS_DX(a0)
	move.l HS_DZ(a0),d0
	asr.l #8,d0
	add.l d0,-$66fc(a4)
	andi.l #255,HS_DZ(a0)
	move.w -$66b6(a4),HS_LAST_HEAD(a0)
	movem.l (a7)+,d2-d7/a2-a3
	move.l _handling_tail(pc),-(a7)
	rts

; D0 = whole heading units the model turned. The car turns about its own
; vertical axis, which stays where it is: on a slope the tilt turns with the
; car, as a pair (pitch, roll) rotated by the turn, and keeps its size. The
; native yaw-rate helper ($B1D0) adds -r sin(roll) to pitch and -r sin(pitch)
; to roll instead, which makes any tilt grow at the turn rate; the contact
; code wins against that at the native turn rates, not at the model's. It is
; kept above 60 degrees of pitch or roll, as in the loop, where its inverted
; heading factor matters. Clobbers D0-D5/A0-A1.
_handling_turn:
	move.w -$66b4(a4),d2		; pitch G($994C)
	bsr .wrap
	move.w d2,d3
	move.w -$66b2(a4),d2		; roll G($994E)
	bsr .wrap
	move.w d3,d1
	bpl.s .pitch
	neg.w d1
.pitch:
	cmpi.w #240,d1
	bge.s .native
	move.w d2,d1
	bpl.s .roll
	neg.w d1
.roll:
	cmpi.w #240,d1
	bge.s .native
	; the enhanced angle fractions stay, as for the native helper's adds
	movea.l _handling_motion(pc),a1
	add.w d0,-$66b6(a4)		; heading G($994A), wrapped by the tail
	add.w d0,MS_YAW+4(a1)
	; native sine and cosine, Q14; they clobber D0/D1/A0, and the cosine
	; adds 360 to its argument in place, so it goes second
	move.w d0,-(a7)
	jsr -$7f26(a4)
	move.w d0,d5
	jsr -$7f2c(a4)
	addq.w #2,a7
	move.w d0,d4
	; pitch' = pitch cos - roll sin, roll' = pitch sin + roll cos, rounded
	move.w d3,d0
	muls.w d4,d0
	move.w d2,d1
	muls.w d5,d1
	sub.l d1,d0
	addi.l #1<<13,d0
	moveq #14,d1
	asr.l d1,d0
	sub.w d3,d0
	add.w d0,-$66b4(a4)
	add.w d0,MS_PITCH+4(a1)
	move.w d3,d0
	muls.w d5,d0
	move.w d2,d1
	muls.w d4,d1
	add.l d1,d0
	addi.l #1<<13,d0
	moveq #14,d1
	asr.l d1,d0
	sub.w d2,d0
	add.w d0,-$66b2(a4)
	add.w d0,MS_ROLL+4(a1)
	rts
.native:
	movea.l _handling_fields(pc),a1
	move.w (a1),-(a7)
	move.w #8,(a1)
	move.w d0,-(a7)
	movea.l _handling_yaw_rate(pc),a1
	jsr (a1)
	movea.l _handling_fields(pc),a1
	move.w (a7)+,(a1)
	rts
; D2 = angle, returned within -720..720
.wrap:
	cmpi.w #720,d2
	ble.s .wrap_high
	subi.w #1440,d2
.wrap_high:
	cmpi.w #-720,d2
	bge.s .wrap_low
	addi.w #1440,d2
.wrap_low:
	rts

; A0 = state. Frame bookkeeping, resets and the step inputs other than the
; mouse. Clobbers D0-D4/A1.
_handling_sync:
	movea.l _handling_time(pc),a1
	move.l TS_PASSES(a1),d0
	move.l d0,d1
	sub.l HS_PASS(a0),d1
	beq.s .same_frame
	move.l d0,HS_PASS(a0)
	subq.l #1,d1
	beq.s .next_frame
	bsr _handling_reset		; a pass without steering: crash, start
.next_frame:
	movea.l _handling_time(pc),a1
	move.l TS_PREVIOUS(a1),d0
	move.l TS_ELAPSED(a1),d1
	sub.l d1,d0
	addq.l #1,d0
	move.l d0,HS_INDEX(a0)
	moveq #0,d0
	subi.l #HANDLING_CAP,d1
	bls.s .no_skip
	move.l d1,d0
.no_skip:
	move.w d0,HS_SKIP(a0)
	sf HS_SKID(a0)
.same_frame:
	; any other heading writer (start, recovery, replay) resets the model
	move.w -$66b6(a4),d0
	sub.w HS_LAST_HEAD(a0),d0
	beq.s .heading
	cmpi.w #1440,d0
	beq.s .heading
	cmpi.w #-1440,d0
	beq.s .heading
	bsr _handling_reset
.heading:
	; velocity eighths, with the phase solver's fraction when it is current
	sf HS_PHASE(a0)
	move.w -$66d8(a4),d0
	lea _phase_state(pc),a1
	tst.w PH_VALID(a1)
	beq.s .word_speed
	cmp.w PH_CURRENT_V(a1),d0
	bne.s .word_speed
	st HS_PHASE(a0)
	move.l PH_CURRENT_V(a1),d0
	moveq #13,d1
	asr.l d1,d0
	bra.s .speed
.word_speed:
	ext.l d0
	asl.l #3,d0
.speed:
	cmpi.l #HANDLING_V8_MAX,d0
	ble.s .speed_high
	move.l #HANDLING_V8_MAX,d0
.speed_high:
	cmpi.l #-HANDLING_V8_MAX,d0
	bge.s .speed_low
	move.l #-HANDLING_V8_MAX,d0
.speed_low:
	move.w d0,d2
	muls.w #HM_K_U,d0
	moveq #13,d1
	asr.l d1,d0
	move.w d0,HS_UBASE(a0)
	clr.l HS_DU(a0)
	; the native net force over the last call's fields, held for this one
	move.w d2,d0
	sub.w HS_V8(a0),d0
	move.w d2,HS_V8(a0)
	move.w HS_NPREV(a0),d1
	movea.l _handling_fields(pc),a1
	move.w (a1),HS_NPREV(a0)
	tst.w d1
	beq.s .no_force
	move.w d1,d3
	mulu.w #HANDLING_JUMP,d3
	move.w d0,d4
	bpl.s .change
	neg.w d4
.change:
	cmp.w d3,d4
	bls.s .force
	bsr _handling_reset		; collision: the speed jumped
.no_force:
	moveq #0,d0
	bra.s .limit
.force:
	move.w d0,d4			; the change in eighths, over d3 fields
	move.w d1,d3
	ext.l d0
	asl.l #4,d0
	divs.w d1,d0
	muls.w #HANDLING_K_FX,d0
	asr.l #4,d0
.limit:
	moveq #0,d1
	tst.w d0
	bpl.s .drive
	tst.b -$66ef(a4)
	beq.s .coast
	cmpi.w #-HANDLING_FX_BRAKE,d0
	bge.s .brake
	move.w #-HANDLING_FX_BRAKE,d0
.brake:
	move.w d0,d1
	bra.s .inputs
.coast:
	cmpi.w #-HANDLING_FX_COAST,d0
	bge.s .inputs
	move.w #-HANDLING_FX_COAST,d0
	bra.s .inputs
.drive:
	cmpi.w #HANDLING_FX_DRIVE,d0
	ble.s .inputs
	; What the native engine gained beyond the drive limit never went
	; through the tyres. While they have grip to spare it stays, so the
	; native car keeps its acceleration. While a tyre is past its peak it
	; comes off again: the engine is power limited and pushes hardest when
	; the model has taken speed away, and pushing a sliding car along its
	; heading feeds v r a spin that never ends.
	move.b HS_FRONT+AX_PEAK(a0),d1
	or.b HS_REAR+AX_PEAK(a0),d1
	beq.s .grip
	mulu.w #HANDLING_FX_DRIVE,d3
	addi.l #HANDLING_K_FX/2,d3
	divu.w #HANDLING_K_FX,d3	; eighths the limit gives
	sub.w d3,d4			; eighths beyond it
	ble.s .grip
	muls.w #-HM_K_U,d4
	asl.l #3,d4			; Q22 ft/s
	move.l d4,HS_DU(a0)
.grip:
	moveq #0,d1
	move.w #HANDLING_FX_DRIVE,d0
.inputs:
	move.w d0,HS_FXIN(a0)
	move.w d1,HS_BRAKE(a0)
	; wheels 0-1 are the front pair, as native steering tests them
	moveq #0,d1
	move.b -$66f0(a4),d0
	moveq #3,d2
	and.b d0,d2
	beq.s .front_air
	moveq #1,d1
.front_air:
	andi.b #12,d0
	beq.s .rear_air
	addq.w #2,d1
.rear_air:
	move.w d1,HS_CONTACT(a0)
	rts

; A0 = state. The forward speed the model added in this call (cornering
; drag, slides, wheelspin, v r) goes back to the native speed: a phase
; solver that is current gets it in its anchor and current velocity, so
; the native engine goes on from the new speed; otherwise it goes into
; G($9928). The native engine steps from the anchor's whole speed word and
; a phase ends on its whole endpoint, so only whole units are applied and
; the fraction waits for later calls. The speed stops at zero rather than
; changing sign. Clobbers D0-D2/A1.
_handling_feedback:
	move.l HS_DU(a0),d0
	clr.l HS_DU(a0)
	move.w d0,d1
	swap d0
	muls.w #HANDLING_K_PH,d0
	mulu.w #HANDLING_K_PH,d1
	clr.w d1
	swap d1
	add.l d1,d0
	add.l HS_CARRY(a0),d0
	moveq #0,d1
	move.w d0,d1
	move.l d1,HS_CARRY(a0)
	clr.w d0
	tst.l d0
	beq.s .done
	lea _phase_state(pc),a1
	tst.b HS_PHASE(a0)
	beq.s .word
	move.l PH_CURRENT_V(a1),d1
	bsr.s .add
	add.l d0,PH_CURRENT_V(a1)
	move.l PH_ANCHOR_V(a1),d1
	bsr.s .add
	add.l d0,PH_ANCHOR_V(a1)
	move.w PH_CURRENT_V(a1),-$66d8(a4)
	move.l PH_CURRENT_V(a1),d0
	moveq #13,d1
	asr.l d1,d0
	bra.s .eighths
.word:
	move.w -$66d8(a4),d1
	swap d1
	clr.w d1
	bsr.s .add
	add.l d1,d0
	swap d0
	move.w d0,-$66d8(a4)
	ext.l d0
	asl.l #3,d0
.eighths:
	; the next force measurement starts from the speed the model left
	cmpi.l #HANDLING_V8_MAX,d0
	ble.s .eighths_high
	move.l #HANDLING_V8_MAX,d0
.eighths_high:
	cmpi.l #-HANDLING_V8_MAX,d0
	bge.s .eighths_low
	move.l #-HANDLING_V8_MAX,d0
.eighths_low:
	move.w d0,HS_V8(a0)
.done:
	rts
; D1 = speed, D0 = change; returns in D0 the change that stops at zero
.add:
	move.l d1,d2
	add.l d0,d2
	eor.l d1,d2
	bpl.s .same_sign
	move.l d1,d0
	neg.l d0
.same_sign:
	rts

; A0 = state. Clears the model and starts its bookkeeping from the current
; heading and speed.
_handling_reset:
	movem.l d0/a1,-(a7)
	movea.l a0,a1
	moveq #HS_MODEL/2-1,d0
.clear:
	clr.w (a1)+
	dbf d0,.clear
	clr.l HS_HEAD(a0)
	clr.l HS_DX(a0)
	clr.l HS_DZ(a0)
	clr.w HS_NPREV(a0)
	clr.l HS_DU(a0)
	clr.l HS_CARRY(a0)
	move.w -$66b6(a4),HS_LAST_HEAD(a0)
	movem.l (a7)+,d0/a1
	rts

; One field of the model; the same arithmetic as handling_fx.FxCar.step.
; A0 = state with its inputs set. Clobbers D0-D7/A1-A3.
_handling_step:
	move.w HS_FXIN(a0),d0
	cmpi.w #HM_FX_MAX,d0
	ble.s .fx_high
	move.w #HM_FX_MAX,d0
.fx_high:
	cmpi.w #-HM_FX_MAX,d0
	bge.s .fx_low
	move.w #-HM_FX_MAX,d0
.fx_low:
	move.w d0,HS_FX(a0)
	; load transfer, lagged: dn += ((fx*K_DN - dn) >> 7) * 25
	muls.w #HM_K_DN,d0
	sub.l HS_DN(a0),d0
	asr.l #7,d0
	move.l d0,d1
	lsl.l #3,d1
	add.l d1,d0
	add.l d1,d1
	add.l d1,d0
	add.l HS_DN(a0),d0
	move.l d0,HS_DN(a0)
	moveq #14,d1
	asr.l d1,d0
	move.l #HM_N0,d1
	sub.l d0,d1
	bpl.s .nf_low
	moveq #0,d1
.nf_low:
	cmpi.l #2*HM_N0,d1
	ble.s .nf_high
	move.l #2*HM_N0,d1
.nf_high:
	move.l #HM_N0,d2
	add.l d0,d2
	bpl.s .nr_low
	moveq #0,d2
.nr_low:
	cmpi.l #2*HM_N0,d2
	ble.s .nr_high
	move.l #2*HM_N0,d2
.nr_high:
	btst #0,HS_CONTACT+1(a0)
	bne.s .front_on
	moveq #0,d1
.front_on:
	btst #1,HS_CONTACT+1(a0)
	bne.s .rear_on
	moveq #0,d2
.rear_on:
	move.w d1,HS_NF(a0)
	move.w d2,HS_NR(a0)
	; steering angle; sin and cos by series
	move.w HS_COUNTS(a0),d0
	cmpi.w #320,d0
	ble.s .counts_high
	move.w #320,d0
.counts_high:
	cmpi.w #-320,d0
	bge.s .counts_low
	move.w #-320,d0
.counts_low:
	muls.w #HM_K_DELTA,d0
	moveq #10,d1
	asr.l d1,d0
	move.w d0,d3			; delta
	moveq #14,d7
	move.w d0,d1
	muls.w d1,d1
	asr.l d7,d1			; delta^2
	move.w d1,d2
	muls.w d3,d2
	asr.l d7,d2			; delta^3
	move.w d1,d4
	muls.w d1,d4
	asr.l d7,d4			; delta^4
	muls.w #2731,d2
	asr.l d7,d2
	move.w d3,d0
	sub.w d2,d0
	move.w d0,HS_SD(a0)
	muls.w #683,d4
	asr.l d7,d4
	asr.w #1,d1
	move.w #16384,d0
	sub.w d1,d0
	add.w d4,d0
	move.w d0,HS_CD(a0)
	; contact velocities
	move.w HS_V(a0),d0		; v >> 16
	move.w HS_R(a0),d1		; r >> 16
	move.w d1,HS_RW(a0)
	muls.w #5,d1
	asr.l #5,d1
	move.w d0,d2
	add.w d1,d2			; front
	sub.w d1,d0			; rear
	move.w d0,HS_VCR(a0)
	move.w HS_U(a0),d0
	move.w d0,d1
	muls.w HS_CD(a0),d0
	move.w d2,d3
	muls.w HS_SD(a0),d3
	add.l d3,d0
	asr.l d7,d0
	move.w d0,d4			; front wheel frame: along
	move.w d2,d0
	muls.w HS_CD(a0),d0
	muls.w HS_SD(a0),d1
	sub.l d1,d0
	asr.l d7,d0
	move.w d0,d5			; and across
	; brake fade s(w), Q14: the sliding wheel's speed, else the road's
	lea HS_FRONT(a0),a1
	move.w d4,d0
	tst.b AX_SLIDE(a1)
	beq.s .rolling_speed
	move.w AX_W(a1),d0
.rolling_speed:
	move.w d0,d1
	bpl.s .speed_abs
	neg.w d1
.speed_abs:
	moveq #0,d3
	cmpi.w #128,d1
	blt.s .fade
	move.w #16384,d3
	cmpi.w #640,d1
	bge.s .fade
	move.w d1,d3
	muls.w #13107,d3
	moveq #10,d6
	asr.l d6,d3
.fade:
	tst.w d0
	bpl.s .fade_sign
	neg.w d3
.fade_sign:
	muls.w HS_BRAKE(a0),d3
	asr.l d7,d3
	move.w d3,d7
	move.w HS_NF(a0),d6
	lea _handling_front(pc),a2
	bsr _handling_axle
	; front force in body axes. The rear wheels get fx less the front
	; wheel's own longitudinal force: fx is the native drive, and the drag
	; of the steered front tyre is the model's (handling_fx fx_total=False)
	moveq #14,d7
	move.w d0,d2
	muls.w HS_CD(a0),d2
	move.l d2,d4
	asr.l d7,d4
	move.w d1,d3
	muls.w HS_SD(a0),d3
	sub.l d3,d2
	asr.l d7,d2
	move.w d2,HS_FXBF(a0)
	muls.w HS_SD(a0),d0
	muls.w HS_CD(a0),d1
	add.l d1,d0
	asr.l d7,d0
	move.w d0,HS_FYBF(a0)
	move.w HS_FX(a0),d0
	ext.l d0
	sub.l d4,d0
	cmpi.l #HM_FX_MAX,d0
	ble.s .rt_high
	move.l #HM_FX_MAX,d0
.rt_high:
	cmpi.l #-HM_FX_MAX,d0
	bge.s .rt_low
	move.l #-HM_FX_MAX,d0
.rt_low:
	muls.w #HM_K_UNROLL,d0
	asr.l d7,d0
	move.w d0,d7
	move.w HS_U(a0),d4
	move.w HS_VCR(a0),d5
	move.w HS_NR(a0),d6
	lea HS_REAR(a0),a1
	lea _handling_rear(pc),a2
	bsr _handling_axle
	move.w d1,HS_FYR(a0)
	; forward speed beyond fx: the tyres' deviation from it, and v r
	add.w HS_FXBF(a0),d0
	sub.w HS_FX(a0),d0
	muls.w #HM_K_DT_M,d0
	move.w HS_V(a0),d1
	muls.w HS_RW(a0),d1
	asr.l #3,d1
	add.l d1,d0
	asl.l #2,d1
	add.l d1,d0
	move.l d0,HS_DUF(a0)
	; integrate: the heading from the old yaw rate, then the rates
	move.w HS_RW(a0),d0
	muls.w #HM_K_PSI,d0
	add.l HS_PSI(a0),d0
	cmpi.l #720<<16,d0
	ble.s .psi_high
	subi.l #1440<<16,d0
	bra.s .psi_done
.psi_high:
	cmpi.l #-720<<16,d0
	bge.s .psi_done
	addi.l #1440<<16,d0
.psi_done:
	move.l d0,HS_PSI(a0)
	move.w HS_U(a0),d0
	muls.w HS_RW(a0),d0
	asr.l #3,d0
	move.l d0,d1
	asl.l #2,d1
	add.l d1,d0			; 5 (u r >> 3)
	move.w HS_FYBF(a0),d1
	muls.w #HM_K_DT_M,d1
	move.w HS_FYR(a0),d2
	muls.w #HM_K_DT_M,d2
	add.l d2,d1
	sub.l d0,d1
	add.l HS_V(a0),d1
	cmpi.l #HM_V_MAX,d1
	ble.s .v_high
	move.l #HM_V_MAX,d1
.v_high:
	cmpi.l #-HM_V_MAX,d1
	bge.s .v_low
	move.l #-HM_V_MAX,d1
.v_low:
	move.l d1,HS_V(a0)
	move.w HS_FYBF(a0),d0
	muls.w #HM_K_DT_I,d0
	move.w HS_FYR(a0),d1
	muls.w #HM_K_DT_I,d1
	sub.l d1,d0
	add.l HS_R(a0),d0
	cmpi.l #HM_R_MAX,d0
	ble.s .r_high
	move.l #HM_R_MAX,d0
.r_high:
	cmpi.l #-HM_R_MAX,d0
	bge.s .r_low
	move.l #-HM_R_MAX,d0
.r_low:
	move.l d0,HS_R(a0)
	move.w HS_FYBF(a0),d0
	add.w HS_FYR(a0),d0
	move.w d0,HS_FYSUM(a0)
	rts

; One axle's tyre and wheel. D4 = contact velocity along the wheel, D5 =
; across it (Q6), D6 = load (Q2 lb), D7 = torque (lb ft); A1 = axle state,
; A2 = constants (mu Q14, C'/3 Q8, 2k dt/C' Q8, k/C' Q4). Returns the
; wheel-frame forces Fx in D0 and Fy in D1 (lb, sign-extended words).
; Clobbers D2/D3/D6/D7/A3.
_handling_axle:
	sf AX_PEAK(a1)
	tst.w d6
	bgt.s .loaded
	clr.l AX_Y(a1)
	sf AX_SLIDE(a1)
	moveq #0,d0
	moveq #0,d1
	rts
.loaded:
	move.w (a2),d3
	mulu.w d6,d3
	swap d3				; mu N
	tst.b AX_SLIDE(a1)
	beq .rolling
	move.w AX_W(a1),d0		; w >> 16
	cmp.w d4,d0
	ble.s .slower
	; spinning: the torque less mu N drives the wheel towards the road
	move.w d7,d0
	sub.w d3,d0
	ext.l d0
	moveq #13,d1
	asl.l d1,d0
	add.l AX_W(a1),d0
	move.w d4,d1
	addi.w #HM_SLIP_MAX,d1
	swap d1
	clr.w d1
	cmp.l d1,d0
	ble.s .spin_limit
	move.l d1,d0
.spin_limit:
	move.l d0,AX_W(a1)
	swap d0
	cmp.w d4,d0
	bgt.s .slide
	bra.s .grips
.slower:
	; locking: the torque plus mu N
	move.w d7,d0
	add.w d3,d0
	ext.l d0
	moveq #13,d1
	asl.l d1,d0
	add.l AX_W(a1),d0
	move.w d4,d1
	subi.w #HM_SLIP_MAX,d1
	swap d1
	clr.w d1
	cmp.l d1,d0
	bge.s .lock_limit
	move.l d1,d0
.lock_limit:
	move.l d0,AX_W(a1)
	swap d0
	cmp.w d4,d0
	blt.s .slide
.grips:
	sf AX_SLIDE(a1)
	bra .rolling
.slide:
	; the whole mu N against the slip velocity (u - w, v)
	st AX_PEAK(a1)
	move.w d4,d1
	sub.w d0,d1			; su
	move.w d1,d0
	muls.w d0,d0
	move.w d5,d2
	muls.w d2,d2
	add.l d2,d0
	bsr _handling_isqrt
	tst.w d0
	beq.s .no_slip
	move.w d3,d2
	muls.w d1,d2
	divs.w d0,d2
	neg.w d2
	muls.w d5,d3
	divs.w d0,d3
	neg.w d3
	move.w d2,d0
	ext.l d0
	move.w d3,d1
	ext.l d1
	rts
.no_slip:
	moveq #0,d0
	moveq #0,d1
	rts
.rolling:
	move.w d7,d0
	muls.w #HM_K_ROLL,d0
	moveq #15,d1
	asr.l d1,d0			; t
	move.l d0,d1
	bpl.s .t_abs
	neg.l d1
.t_abs:
	moveq #0,d2
	move.w d3,d2
	cmp.l d2,d1
	blt.s .grip
	; the torque exceeds mu N: the wheel starts to slide
	st AX_PEAK(a1)
	st AX_SLIDE(a1)
	move.w d7,d1
	tst.l d0
	bmi.s .start_back
	sub.w d3,d1
	bra.s .start
.start_back:
	add.w d3,d1
	neg.l d2
.start:
	ext.l d1
	moveq #13,d6
	asl.l d6,d1
	cmpi.l #HM_SLIP_MAX<<16,d1
	ble.s .start_high
	move.l #HM_SLIP_MAX<<16,d1
.start_high:
	cmpi.l #-(HM_SLIP_MAX<<16),d1
	bge.s .start_low
	move.l #-(HM_SLIP_MAX<<16),d1
.start_low:
	move.w d4,d6
	swap d6
	clr.w d6
	add.l d6,d1
	move.l d1,AX_W(a1)
	move.l d2,d0
	moveq #0,d1
	rts
.grip:
	move.w d0,d7			; Fx = t
	; friction circle: mu' = mu sqrt(1 - (Fx/mu N)^2)
	move.w (a2),d2
	tst.w d7
	beq.s .circle_done
	moveq #0,d0
	move.w d7,d0
	bpl.s .fx_abs
	neg.w d0
.fx_abs:
	moveq #14,d1
	lsl.l d1,d0
	divu.w d3,d0
	moveq #0,d1
	move.w d0,d1
	lsr.w #6,d1
	andi.w #63,d0
	add.w d1,d1
	lea _handling_circle(pc),a3
	adda.w d1,a3
	move.w (a3)+,d1
	move.w (a3),d2
	sub.w d1,d2
	muls.w d0,d2
	asr.l #6,d2
	add.w d1,d2
	muls.w (a2),d2
	moveq #14,d1
	asr.l d1,d2
.circle_done:
	move.w d2,d0
	mulu.w d6,d0
	swap d0
	move.w d0,d3			; mu' N
	move.w d4,d1
	bpl.s .uw_abs
	neg.w d1
.uw_abs:
	cmpi.w #64,d1
	bge.s .auw
	moveq #64,d1
.auw:
	move.w d5,d0
	bpl.s .vw_abs
	neg.w d0
.vw_abs:
	mulu.w 2(a2),d0			; a = |v| C'/3
	mulu.w d2,d1			; b = mu' |u|
	tst.w d2
	beq .past
	; past the peak when a << 6 >= b
	cmpi.l #$01000000,d0
	bhs .past
	movea.l d0,a3
	lsl.l #6,d0
	cmp.l d1,d0
	bhs .past
	move.l a3,d0
	; z: the slip as a share of the peak slip, Q14
	cmpi.l #$01000000,d1
	blo.s .z_small
	lsl.l #7,d0
	moveq #13,d2
	lsr.l d2,d1
	bra.s .z_divide
.z_small:
	moveq #11,d2
	lsl.l d2,d0
	moveq #9,d2
	lsr.l d2,d1
.z_divide:
	divu.w d1,d0
	cmpi.w #16383,d0
	bls.s .z_ok
	move.w #16383,d0
.z_ok:
	move.w d0,d2
	movea.w d0,a3			; z
	; secant g = 1 - z + z^2/3
	muls.w d0,d0
	moveq #14,d1
	asr.l d1,d0
	muls.w #5461,d0
	asr.l d1,d0
	addi.w #16384,d0
	sub.w d2,d0
	; the lag runs while |u| k dt < secant/2
	move.w d4,d1
	bpl.s .lag_abs
	neg.w d1
.lag_abs:
	mulu.w 4(a2),d1			; |u| Kd
	move.w d6,d2
	mulu.w d0,d2			; N g
	move.l d2,d0
	lsr.l #2,d0
	cmp.l d0,d1
	bhs.s .curve
	; deflection lags: y' = -y |u| k / (N g C') - v
	clr.w d2
	swap d2
	move.w d4,d0
	bpl.s .rate_abs
	neg.w d0
.rate_abs:
	mulu.w 6(a2),d0
	divu.w d2,d0			; Q10 1/s
	move.w AX_Y(a1),d1		; y >> 16
	muls.w d0,d1
	moveq #15,d2
	asr.l d2,d1
	neg.l d1
	sub.w d5,d1
	bsr.s .spring
	ext.l d1
	move.w d7,d0
	ext.l d0
	rts
.curve:
	; steady curve: Fy = mu' N (1 - (1 - z)^3) against the slip, y = Fy/k
	move.w #16384,d0
	sub.w a3,d0
	move.w d0,d1
	muls.w d0,d1
	moveq #14,d2
	asr.l d2,d1
	muls.w d0,d1
	asr.l d2,d1
	move.w #16384,d0
	sub.w d1,d0
	muls.w d3,d0
	asr.l d2,d0
	tst.w d5
	ble.s .curve_sign
	neg.l d0
.curve_sign:
	move.w d0,d1
	muls.w #HM_K_Y,d0
	move.l d0,AX_Y(a1)
	ext.l d1
	move.w d7,d0
	ext.l d0
	rts
.past:
	st AX_PEAK(a1)
	move.w d5,d1
	neg.w d1
	bsr.s .spring
	moveq #0,d0
	move.w d3,d0
	tst.l d1
	bmi.s .past_back
	cmp.l d0,d1
	ble.s .past_done
	move.l d0,d1
	bra.s .past_limit
.past_back:
	neg.l d0
	cmp.l d0,d1
	bge.s .past_done
	move.l d0,d1
.past_limit:
	move.w d1,d0
	muls.w #HM_K_Y,d0
	move.l d0,AX_Y(a1)
.past_done:
	move.w d7,d0
	ext.l d0
	rts
; D1.w = y'. y += 5 y' << 13, clamped; returns Fy = k y + c y' in D1.l.
.spring:
	move.w d1,d0
	ext.l d0
	move.l d0,d2
	asl.l #2,d0
	add.l d2,d0
	moveq #13,d2
	asl.l d2,d0
	add.l AX_Y(a1),d0
	cmpi.l #HM_Y_MAX,d0
	ble.s .y_high
	move.l #HM_Y_MAX,d0
.y_high:
	cmpi.l #-HM_Y_MAX,d0
	bge.s .y_low
	move.l #-HM_Y_MAX,d0
.y_low:
	move.l d0,AX_Y(a1)
	swap d0
	muls.w #HM_K,d0
	moveq #11,d2
	asr.l d2,d0
	muls.w #25,d1
	asr.l #2,d1
	add.l d0,d1
	rts

; D0.l unsigned -> D0.l = floor(sqrt). Preserves D1-D7.
_handling_isqrt:
	movem.l d1-d3,-(a7)
	moveq #0,d1
	move.l #$40000000,d2
.bit:
	move.l d1,d3
	add.l d2,d3
	lsr.l #1,d1
	cmp.l d3,d0
	blo.s .next
	sub.l d3,d0
	add.l d2,d1
.next:
	lsr.l #2,d2
	bne.s .bit
	move.l d1,d0
	movem.l (a7)+,d1-d3
	rts

_handling_front: dc.w 19661,1549,4494,7191
_handling_rear: dc.w 21299,3099,2247,3595
; sqrt(1 - x^2) at x = i/256, Q14
_handling_circle:
	dc.w 16384,16384,16383,16383,16382,16381,16379,16378,16376,16374,16371,16369,16366,16363,16359,16356
	dc.w 16352,16348,16343,16339,16334,16329,16323,16318,16312,16306,16299,16293,16286,16279,16271,16263
	dc.w 16255,16247,16239,16230,16221,16212,16202,16193,16183,16173,16162,16151,16140,16129,16117,16106
	dc.w 16093,16081,16068,16056,16042,16029,16015,16001,15987,15973,15958,15943,15928,15912,15896,15880
	dc.w 15864,15847,15830,15813,15795,15778,15760,15741,15723,15704,15685,15665,15645,15625,15605,15584
	dc.w 15563,15542,15521,15499,15477,15455,15432,15409,15386,15362,15338,15314,15289,15265,15240,15214
	dc.w 15188,15162,15136,15109,15082,15055,15027,14999,14971,14942,14914,14884,14855,14825,14794,14764
	dc.w 14733,14701,14670,14638,14605,14573,14540,14506,14472,14438,14404,14369,14334,14298,14262,14226
	dc.w 14189,14152,14114,14076,14038,13999,13960,13921,13881,13840,13800,13759,13717,13675,13632,13590
	dc.w 13546,13502,13458,13414,13368,13323,13277,13230,13183,13136,13088,13040,12991,12941,12891,12841
	dc.w 12790,12738,12686,12634,12581,12527,12473,12418,12362,12306,12250,12193,12135,12077,12018,11958
	dc.w 11898,11837,11775,11713,11650,11586,11522,11457,11391,11325,11257,11189,11121,11051,10980,10909
	dc.w 10837,10764,10690,10615,10540,10463,10385,10307,10227,10147,10065,9982,9898,9813,9727,9640
	dc.w 9551,9461,9370,9278,9184,9089,8992,8894,8794,8692,8589,8485,8378,8269,8159,8046
	dc.w 7932,7815,7696,7574,7450,7324,7194,7062,6926,6787,6645,6499,6349,6194,6035,5871
	dc.w 5701,5526,5344,5155,4957,4751,4535,4306,4064,3805,3526,3222,2885,2501,2044,1447
	dc.w 0
_handling_signature: dc.b 'HDHAND01'
_handling_state: dcb.b HS_SIZE,0
_handling_ring: dcb.w HANDLING_RING,0

	IFD VERIFY_HANDLING_MATH
; Boot fixture: HANDLING_MATH_RUNS sequences of HANDLING_MATH_FIELDS steps
; through _handling_step with xorshift32 inputs, in a private state block.
; Each sequence publishes a checksum of the model state after every step and
; its final v, r and heading. check_handling_math.py replays the same inputs
; through handling_fx.py. No game state is touched.
HANDLING_MATH_RUNS equ 64
HANDLING_MATH_FIELDS equ 250
HMV_X equ 0			; generator state
HMV_CHECK equ 4			; checksum
HMV_V8 equ 8
HMV_M equ 10
HMV_FX equ 12
HMV_BRAKE equ 14
HMV_CONTACT equ 16
HMV_RUN equ 18
HMV_FIELD equ 20
_handling_math_test:
	movem.l d0-d7/a0-a6,-(a7)
	lea _handling_math_vars(pc),a4
	move.l #$2545f491,HMV_X(a4)
	lea _handling_math_results(pc),a5
	move.w #HANDLING_MATH_RUNS,HMV_RUN(a4)
.run:
	lea _handling_math_state(pc),a0
	moveq #HS_MODEL/2-1,d0
.clear:
	clr.w (a0)+
	dbf d0,.clear
	bsr .next
	lsr.l #8,d0
	andi.w #4095,d0
	move.w d0,HMV_V8(a4)
	clr.w HMV_M(a4)
	clr.w HMV_FX(a4)
	clr.w HMV_BRAKE(a4)
	move.w #3,HMV_CONTACT(a4)
	clr.l HMV_CHECK(a4)
	move.w #HANDLING_MATH_FIELDS,HMV_FIELD(a4)
.field:
	bsr .next
	move.l d0,d2
	moveq #31,d1
	and.w d2,d1
	bne.s .keep_mouse
	move.l d2,d0
	lsr.l #5,d0
	andi.l #1023,d0
	divu.w #641,d0
	swap d0
	subi.w #320,d0
	move.w d0,HMV_M(a4)
.keep_mouse:
	move.l d2,d0
	moveq #15,d1
	lsr.l d1,d0
	andi.w #31,d0
	bne.s .keep_brake
	move.l d2,d0
	moveq #20,d1
	lsr.l d1,d0
	andi.w #4095,d0
	neg.w d0
	move.w d0,HMV_BRAKE(a4)
.keep_brake:
	move.l d2,d0
	lsr.l #8,d0
	lsr.l #2,d0
	andi.w #31,d0
	cmpi.w #1,d0
	bne.s .keep_force
	move.l d2,d0
	swap d0
	move.w d0,HMV_FX(a4)
.keep_force:
	move.w d2,d0
	andi.w #1023,d0
	cmpi.w #1023,d0
	bne.s .keep_contact
	move.l d2,d0
	moveq #12,d1
	lsr.l d1,d0
	andi.w #3,d0
	move.w d0,HMV_CONTACT(a4)
.keep_contact:
	move.l d2,d0
	moveq #26,d1
	lsr.l d1,d0
	subi.w #32,d0
	add.w HMV_V8(a4),d0
	cmpi.w #-200,d0
	bge.s .v8_low
	move.w #-200,d0
.v8_low:
	cmpi.w #HANDLING_V8_MAX,d0
	ble.s .v8_high
	move.w #HANDLING_V8_MAX,d0
.v8_high:
	move.w d0,HMV_V8(a4)
	muls.w #HM_K_U,d0
	moveq #13,d1
	asr.l d1,d0
	lea _handling_math_state(pc),a0
	move.w d0,HS_U(a0)
	move.w HMV_M(a4),HS_COUNTS(a0)
	move.w HMV_FX(a4),HS_FXIN(a0)
	move.w HMV_BRAKE(a4),HS_BRAKE(a0)
	move.w HMV_CONTACT(a4),HS_CONTACT(a0)
	bsr _handling_step
	move.l HS_V(a0),d0
	bsr .mix
	move.l HS_R(a0),d0
	bsr .mix
	move.l HS_DN(a0),d0
	bsr .mix
	move.l HS_PSI(a0),d0
	bsr .mix
	lea HS_FRONT(a0),a1
	bsr .axle
	lea HS_REAR(a0),a1
	bsr .axle
	move.w HS_FYSUM(a0),d0
	ext.l d0
	bsr .mix
	move.l HS_DUF(a0),d0
	bsr .mix
	subq.w #1,HMV_FIELD(a4)
	bne .field
	move.l HMV_CHECK(a4),(a5)+
	move.l HS_V(a0),(a5)+
	move.l HS_R(a0),(a5)+
	move.l HS_PSI(a0),(a5)+
	subq.w #1,HMV_RUN(a4)
	bne .run
	movem.l (a7)+,d0-d7/a0-a6
	rts
; A1 = axle: deflection, wheel speed while sliding, slide + 2 peak
.axle:
	move.l AX_Y(a1),d0
	bsr.s .mix
	moveq #0,d0
	tst.b AX_SLIDE(a1)
	beq.s .rolling
	move.l AX_W(a1),d0
.rolling:
	bsr.s .mix
	moveq #0,d0
	tst.b AX_SLIDE(a1)
	beq.s .flags
	moveq #1,d0
.flags:
	tst.b AX_PEAK(a1)
	beq.s .mix
	addq.l #2,d0
; checksum = rol(checksum, 5) + D0
.mix:
	move.l HMV_CHECK(a4),d1
	rol.l #5,d1
	add.l d0,d1
	move.l d1,HMV_CHECK(a4)
	rts
; xorshift32 in HMV_X; returns it in D0
.next:
	move.l HMV_X(a4),d0
	move.l d0,d1
	moveq #13,d3
	lsl.l d3,d1
	eor.l d1,d0
	move.l d0,d1
	moveq #17,d3
	lsr.l d3,d1
	eor.l d1,d0
	move.l d0,d1
	lsl.l #5,d1
	eor.l d1,d0
	move.l d0,HMV_X(a4)
	rts
_handling_math_vars: dcb.b 22,0
_handling_math_state: dcb.b HS_MODEL,0
_handling_math_signature: dc.b 'HDHANDM1'
_handling_math_results: dcb.l HANDLING_MATH_RUNS*4,0
	ENDC
