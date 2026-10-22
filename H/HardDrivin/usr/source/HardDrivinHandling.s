; Arcade handling, CUSTOM1=2: a two-wheel car model replaces the native
; steering and skid, and the arcade's drivetrain the native engine. It
; steps once per PAL field (dt 1/50 s); a frame that took n fields runs n
; steps, each with its own field's mouse X. The model turns the car, adds
; its sideways motion and sets the forward speed from its tyres, drag and
; gravity, publishing the speed, RPM, gear and speedometer the native engine
; did. Every hook is installed only for CUSTOM1=2, so the other settings run
; exactly the release code.

	IFND VERIFY_DRIVETRAIN_PHASE
	FAIL "VERIFY_HANDLING requires VERIFY_DRIVETRAIN_PHASE"
	ENDC

HANDLING_CAP equ 50		; steps a frame may catch up, 1 s
HANDLING_RING equ 64		; mouse samples kept, a power of two
HANDLING_V8_MAX equ 4160	; velocity eighths the model accepts, 145 MPH
HANDLING_JUMP equ 40		; eighths per field: a faster change is a reset
HANDLING_FX_BRAKE equ 2470	; front brake torque, lb ft (0.7 g)
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

; The arcade's drivetrain ($730490, ARCADE_ROMS.md), per field. Engine and
; driveline speeds are Q16 rad/s longs, torques lb ft.
HE_DT_IE equ 3200		; lb ft -> Q16 rad/s of engine speed (inertia 0.4)
HE_SLIP equ 686290		; 10.472 rad/s: the driveline overruns the engine
HE_TAKEUP equ 10294362		; 157.08 rad/s: the clutch takes up over 1500-3000 rpm
HE_CAP equ 600			; clutch capacity, lb ft
HE_K_CAP equ 978		; Q8 rad/s past the take-up -> lb ft, after >> 16
HE_K_RPM equ 39114		; Q4 rad/s -> rpm, after >> 16
HE_UP equ 49327			; (throttle + 300) * 2 * HE_UP: up-shift, 602.1 (gas + 3) / 4
HE_DOWN equ 60051		; (throttle + 300) * HE_DOWN: down-shift, 366.5 (gas + 3) / 4
HE_SHIFT equ 51			; fields between shifts, one model second
HE_WE_MAX equ 1000<<16		; engine speed limit
HE_RPM_MAX equ 6500		; RPM the native gauges and sound take
HE_K_DRAG equ 570		; (Q4 u)^2 >> 8 -> lb, after >> 16: 0.0087 u^2
HE_ROLL equ 105			; rolling drag, lb
HE_STOP equ 1500		; the forced stop, lb
HE_K_STOP equ 87		; Q6 ft/s -> lb that stops the car in one field
HE_WEIGHT equ 3525		; lb
HE_K_MPH equ 682		; Q6 ft/s -> MPH, after >> 16

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
HS_TREAR equ 72			; input with HS_ENGINE: rear wheel torque, lb ft
HS_FEXT equ 74			; input with HS_ENGINE: drag and gravity, lb
HS_FXT equ 76			; output: the tyres' longitudinal force, lb
HS_ENGINE equ 78		; the drivetrain's inputs replace fx's rear torque
HS_MODEL equ 80			; size of the part the step uses
; Game coupling
HS_HEAD equ 80			; heading not yet applied, Q16
HS_DX equ 84			; sideways motion not yet applied, Q8 long units
HS_DZ equ 88
HS_INDEX equ 92			; next mouse sample, in TS_FIELDS counts
HS_PASS equ 96			; TS_PASSES of the last steering call
HS_SKIP equ 100			; steps this frame leaves out (catch-up cap)
HS_V8 equ 102			; velocity eighths after the last steering call
HS_NPREV equ 104		; fields the last steering call stepped
HS_LAST_HEAD equ 106		; G($994A) after the last steering call
HS_LOOP equ 108			; fields left in this call
HS_SKID equ 110			; tyres screeched in this frame
HS_PHASE equ 111		; the speed came from the phase solver
HS_UBASE equ 112		; native forward speed of this call, Q6 ft/s
HS_DU equ 114			; forward speed the model added in this call, Q22
HS_CARRY equ 118		; native speed not yet applied, Q16 velocity
; Drivetrain, kept through model resets
HS_WE equ 122			; engine speed, Q16 rad/s
HS_GEAR equ 126			; gear, -1: pick the automatic's for the speed
HS_SHIFT equ 128		; fields until the automatic may shift again
HS_LOCKED equ 130		; the clutch is locked
HS_STOP equ 131			; the forced stop holds the car
HS_MPH equ 132			; speedometer, MPH
HS_TARGET equ 134		; the speed in native velocity units
HS_GRASS equ 136		; the car is off the road
HS_SIZE equ 138

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
	adda.l #_contact_arcade-_handling_install,a0
	move.w #1,(a0)
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
	adda.l #_projection_integer_components-_handling_install,a0
	lea _handling_project(pc),a1
	move.l a0,(a1)
	movea.l a3,a0
	adda.l #_flight_held-_handling_install,a0
	lea _handling_flight(pc),a1
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
	; PERF_RANGE VERIFY_HANDLING $0b512 $0066: movement vector, held flight pitch
	PL_PS $b512,_handling_flight_vector
	; PERF_RANGE VERIFY_HANDLING $0b678 $0006: the drivetrain replaces the engine's speed and RPM
	PL_PS $b678,_handling_engine_skip
	; PERF_RANGE VERIFY_HANDLING $0b90c $0006: the drivetrain's automatic shifts
	PL_PS $b90c,_handling_shift_skip
	; PERF_RANGE VERIFY_HANDLING $0ba8a $0006: the drivetrain's speedometer
	PL_PS $ba8a,_handling_speedo
	PL_END
_handling_tail: dc.l 0		; native angle and trig tail, B44E
_handling_time: dc.l 0		; _time_state
_handling_time_vbl: dc.l 0	; _time_vbl
_handling_fields: dc.l 0	; _time_scalar_fields
_handling_yaw_rate: dc.l 0	; _motion_yaw_rate
_handling_motion: dc.l 0	; _motion_state
_handling_project: dc.l 0	; _projection_integer_components
_handling_flight: dc.l 0	; _flight_held

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

; Replaces B512..B577, the native movement vector (1.5v along the pitch and
; heading), with the same words from _projection_integer_components, which
; uses the held flight pitch (_flight_held). D0/D1/A0/A1 are scratch.
_handling_flight_vector:
	move.l d2,-(a7)
	move.w -$66d8(a4),d0
	movea.l _handling_project(pc),a0
	jsr (a0)
	move.w d0,-$66e2(a4)
	move.w d1,-$66e0(a4)
	move.w d2,-$66de(a4)
	move.l (a7)+,d2
	addi.l #$b578-$b518,(a7)
	rts

; The native engine ($B662) after its crash test: the drivetrain has set the
; speed, RPM and automatic gear, so go straight to the gear site at B904,
; where the phase solver advances its phase and a manual gearbox takes the
; player's shifts (B9BA). Its automatic shifts (B90C) give way to the
; drivetrain's, and its speedometer from the RPM (BA8A) to the ground
; speed; the tail from BAC6 clears the brake and sets the engine sound.
_handling_engine_skip:
	addi.l #$b904-$b67e,(a7)
	rts
_handling_shift_skip:
	addi.l #$ba8a-$b912,(a7)
	rts
_handling_speedo:
	lea _handling_state(pc),a0
	move.w HS_MPH(a0),-$66d4(a4)	; G($992C)
	move.w HS_TARGET(a0),-$66da(a4)	; G($9926)
	addi.l #$bac6-$ba90,(a7)
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
	; the native speed plus what the model has added in this call
	move.l HS_DU(a0),d0
	swap d0
	add.w HS_UBASE(a0),d0
	move.w d0,HS_U(a0)
	bsr _handling_engine
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
	bsr _handling_publish
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
	; only the model changes the speed now: a faster change than
	; HANDLING_JUMP per field since the last call is a collision
	move.w d2,d0
	sub.w HS_V8(a0),d0
	move.w d2,HS_V8(a0)
	move.w HS_NPREV(a0),d1
	movea.l _handling_fields(pc),a1
	move.w (a1),HS_NPREV(a0)
	tst.w d1
	beq.s .inputs
	mulu.w #HANDLING_JUMP,d1
	tst.w d0
	bpl.s .change
	neg.w d0
.change:
	cmp.w d1,d0
	bls.s .inputs
	bsr _handling_reset
.inputs:
	; the brake brakes at its limit, on the front, as the arcade's pedal
	moveq #0,d1
	tst.b -$66ef(a4)
	beq.s .no_brake
	move.w #-HANDLING_FX_BRAKE,d1
.no_brake:
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

; A0 = state. The forward speed the model added in this call goes to the
; native speed: a phase solver that is current gets it in its current
; velocity, with its anchor moved there too, since the native engine adds
; nothing now (an anchor with a fraction would make the solver step the
; speed down to its whole word); otherwise it goes into G($9928). Only
; whole units are applied and the fraction waits for later calls. The
; speed may change sign: gravity rolls the car back. Clobbers D0-D2/A1.
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
	lea _phase_state(pc),a1
	tst.b HS_PHASE(a0)
	beq.s .split
	moveq #0,d1
	move.w PH_CURRENT_V+2(a1),d1
	add.l d1,d0
	clr.w PH_CURRENT_V+2(a1)
.split:
	moveq #0,d1
	move.w d0,d1
	move.l d1,HS_CARRY(a0)
	clr.w d0
	tst.b HS_PHASE(a0)
	beq.s .word
	add.l PH_CURRENT_V(a1),d0
	move.l d0,PH_CURRENT_V(a1)
	move.l d0,PH_ANCHOR_V(a1)
	swap d0
	move.w d0,-$66d8(a4)
	bra.s .eighths
.word:
	swap d0
	add.w d0,-$66d8(a4)
	move.w -$66d8(a4),d0
.eighths:
	; the next call's collision test starts from the speed the model left
	ext.l d0
	asl.l #3,d0
	cmpi.l #HANDLING_V8_MAX,d0
	ble.s .eighths_high
	move.l #HANDLING_V8_MAX,d0
.eighths_high:
	cmpi.l #-HANDLING_V8_MAX,d0
	bge.s .eighths_low
	move.l #-HANDLING_V8_MAX,d0
.eighths_low:
	move.w d0,HS_V8(a0)
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

; A0 = state with HS_U and HS_CONTACT set. One field of the arcade's
; drivetrain ($730490): automatic shifts, the engine torque table, the
; automatic clutch, and the rear wheel torque through the gear; then drag
; and gravity. Sets HS_TREAR, HS_FEXT and the step's load transfer force
; (the tyres' force of the last step). Clobbers D0-D7/A1.
_handling_engine:
	tst.b HS_ENGINE(a0)
	bne.s .running
	st HS_ENGINE(a0)		; after a model reset: pick the gear anew
	clr.w HS_SHIFT(a0)
	move.w #-1,HS_GEAR(a0)
.running:
	; the load transfer follows the tyres' force of the last step, and
	; the brake's own while braking, as before the drivetrain: the lag
	; would leave the front light enough to lock as the brake goes on
	move.w HS_FXT(a0),d0
	tst.w HS_BRAKE(a0)
	beq.s .transfer
	move.w HS_BRAKE(a0),d0
.transfer:
	move.w d0,HS_FXIN(a0)
	tst.b -$16b6(a4)		; road G($E94A), else grass
	seq HS_GRASS(a0)
	; throttle 0..100; after the time ran out none and the forced stop,
	; the arcade's engine cut. None while braking: the brake is both
	; buttons, and the throttle they close at 2 per native step would
	; drive against it for seconds.
	moveq #0,d7
	st HS_STOP(a0)
	tst.b -$6864(a4)		; time out G($979C)
	bne.s .gas
	sf HS_STOP(a0)
	tst.b -$66ef(a4)		; brake G($9911)
	bne.s .gas
	move.b -$66e4(a4),d7		; throttle G($991C)
	bpl.s .gas_low
	moveq #0,d7
.gas_low:
	cmpi.w #100,d7
	bls.s .gas
	moveq #100,d7
.gas:
	; the gear: the game's (the native start, manual shifts), the
	; automatic's own shifts at most once a second
	move.w -$66ca(a4),d6		; G($9936)
	tst.b -$66c2(a4)		; automatic G($993E)
	beq .manual
	move.w d7,d4
	addi.w #300,d4
	move.w d4,d5
	mulu.w #HE_UP,d4
	add.l d4,d4			; up-shift engine speed
	mulu.w #HE_DOWN,d5		; down-shift
	tst.w HS_GEAR(a0)
	bpl.s .auto
	; the lowest gear that would not shift up at this speed
	moveq #1,d6
	lea _handling_ratio+2(pc),a1
.pick:
	cmpi.w #4,d6
	beq.s .shifted
	move.w HS_U(a0),d0
	muls.w (a1)+,d0
	cmp.l d4,d0
	ble.s .shifted
	addq.w #1,d6
	bra.s .pick
.auto:
	cmpi.w #1,d6
	bge.s .auto_low
	moveq #1,d6
.auto_low:
	cmpi.w #4,d6
	ble.s .auto_high
	moveq #4,d6
.auto_high:
	tst.w HS_SHIFT(a0)
	beq.s .may_shift
	subq.w #1,HS_SHIFT(a0)
	bra.s .shifted
.may_shift:
	move.l HS_WE(a0),d0
	cmp.l d4,d0
	bls.s .no_up
	cmpi.w #4,d6
	beq.s .shifted
	addq.w #1,d6
	bra.s .lockout
.no_up:
	cmp.l d5,d0
	bhs.s .shifted
	cmpi.w #1,d6
	beq.s .shifted
	subq.w #1,d6
.lockout:
	move.w #HE_SHIFT,HS_SHIFT(a0)
	bra.s .shifted
.manual:
	tst.w d6
	bpl.s .manual_low
	moveq #0,d6
.manual_low:
	cmpi.w #4,d6
	ble.s .shifted
	moveq #4,d6
.shifted:
	move.w d6,HS_GEAR(a0)
	cmp.w -$66ca(a4),d6
	beq.s .same_gear
	move.w d6,-$66ca(a4)
	move.w d6,d0
	lsl.w #3,d0
	lea -$68c6(a4),a1		; the gear's entry, as B9AE/BA86 set it
	adda.w d0,a1
	move.l a1,-$66c0(a4)		; G($9940)
.same_gear:
	; engine torque: the table bilinear over rpm (1000 a column) and
	; throttle (14 of 128 a row), times the gear's factor
	move.l HS_WE(a0),d0
	moveq #12,d1
	lsr.l d1,d0
	mulu.w #HE_K_RPM,d0
	clr.w d0
	swap d0
	divu.w #1000,d0
	cmpi.w #10,d0
	blo.s .column
	move.l #(999<<16)+10,d0
.column:
	move.l d0,d5			; column, its remainder high
	move.w d7,d0
	lsl.w #7,d0
	ext.l d0
	divu.w #100,d0
	andi.l #$ffff,d0
	divu.w #14,d0
	cmpi.w #9,d0
	blo.s .row
	move.l #(13<<16)+8,d0
.row:
	move.l d0,d4			; row, its remainder high
	lea _handling_torque(pc),a1
	tst.b HS_GRASS(a0)
	beq.s .road
	lea _handling_torque_grass-_handling_torque(a1),a1
.road:
	mulu.w #24,d0
	adda.w d0,a1
	adda.w d5,a1
	adda.w d5,a1
	swap d5
	bsr .lerp
	move.w d0,d1
	lea 24(a1),a1
	bsr .lerp
	sub.w d1,d0
	swap d4
	muls.w d4,d0
	divs.w #14,d0
	add.w d1,d0
	move.w d6,d1
	add.w d1,d1
	lea _handling_factor(pc),a1
	tst.b HS_GRASS(a0)
	beq.s .road_factor
	lea 10(a1),a1
.road_factor:
	muls.w (a1,d1.w),d0
	asr.l #8,d0
	asr.l #4,d0
	move.w d0,d7			; engine torque
	; driveline speed: the rear wheel's through the gear
	move.w HS_U(a0),d0
	tst.b HS_REAR+AX_SLIDE(a0)
	beq.s .rolling
	move.w HS_REAR+AX_W(a0),d0
.rolling:
	lea _handling_ratio(pc),a1
	move.w (a1,d1.w),d2		; Q10, zero in neutral
	beq .neutral
	muls.w d2,d0
	move.l d0,d3
	; clutch capacity: full while the driveline overruns the engine,
	; otherwise taking up between 1500 and 3000 rpm
	move.l HS_WE(a0),d1
	subi.l #HE_SLIP,d0
	cmp.l d1,d0
	ble.s .takeup
	move.w #HE_CAP,d4
	bra.s .capacity
.takeup:
	move.l d3,d0
	asr.l #2,d0
	sub.l d0,d1
	subi.l #HE_TAKEUP,d1
	bgt.s .partial
	moveq #0,d4
	bra.s .capacity
.partial:
	cmpi.l #HE_TAKEUP,d1
	blt.s .ramp
	move.w #HE_CAP,d4
	bra.s .capacity
.ramp:
	lsr.l #8,d1
	mulu.w #HE_K_CAP,d1
	swap d1
	move.w d1,d4
.capacity:
	; the clutch slips at its capacity towards the driveline's speed and
	; locks when the engine reaches it; locked it passes the engine torque
	sf HS_LOCKED(a0)
	move.l HS_WE(a0),d1
	cmp.l d3,d1
	ble.s .slower
	move.w d4,d5
	move.w d7,d0
	sub.w d4,d0
	muls.w #HE_DT_IE,d0
	add.l d1,d0
	cmp.l d3,d0
	bge.s .clutched
	move.w d4,d0
	neg.w d0
	cmp.w d7,d0
	ble.s .lock
	move.w d0,d5			; engine braking beyond the capacity
	move.w d7,d0
	add.w d4,d0
	muls.w #HE_DT_IE,d0
	add.l d1,d0
	bra.s .clutched
.slower:
	move.w d4,d5
	neg.w d5
	move.w d7,d0
	add.w d4,d0
	muls.w #HE_DT_IE,d0
	add.l d1,d0
	cmp.l d3,d0
	ble.s .clutched
	cmp.w d4,d7
	ble.s .lock
	move.w d4,d5
	move.w d7,d0
	sub.w d4,d0
	muls.w #HE_DT_IE,d0
	add.l d1,d0
	bra.s .clutched
.lock:
	st HS_LOCKED(a0)
	move.l d3,d0
	move.w d7,d5
.clutched:
	bsr .engine_speed
	; the rear wheel's torque; locked, the engine's inertia through the
	; gear joins the wheel's, as a share of the torque
	muls.w d2,d5
	asr.l #8,d5
	asr.l #2,d5
	tst.b HS_LOCKED(a0)
	beq.s .torque
	move.w d6,d1
	add.w d1,d1
	lea _handling_inertia(pc),a1
	muls.w (a1,d1.w),d5
	moveq #15,d1
	asr.l d1,d5
.torque:
	move.w d5,HS_TREAR(a0)
	bra.s .resist
.neutral:
	move.w d7,d0
	muls.w #HE_DT_IE,d0
	add.l HS_WE(a0),d0
	bsr .engine_speed
	clr.w HS_TREAR(a0)
.resist:
	; drag 0.0087 u^2 + 105 lb, 10 u more on grass, and the forced stop;
	; none of it takes the car past standstill
	moveq #0,d1
	move.w HS_U(a0),d0
	beq.s .gravity
	bpl.s .u_abs
	neg.w d0
.u_abs:
	cmpi.w #16383,d0
	bls.s .u_high
	move.w #16383,d0
.u_high:
	move.w d0,d2
	lsr.w #2,d2
	mulu.w d2,d2
	lsr.l #8,d2
	mulu.w #HE_K_DRAG,d2
	clr.w d2
	swap d2
	addi.w #HE_ROLL,d2
	tst.b HS_GRASS(a0)
	beq.s .paved
	move.w d0,d1
	mulu.w #5,d1
	lsr.l #5,d1
	add.l d1,d2
.paved:
	tst.b HS_STOP(a0)
	beq.s .stop_done
	addi.l #HE_STOP,d2
.stop_done:
	move.w d0,d1
	mulu.w #HE_K_STOP,d1
	cmp.l d1,d2
	bhi.s .limit
	move.l d2,d1
.limit:
	tst.w HS_U(a0)
	bpl.s .gravity
	neg.w d1
.gravity:
	; 1 g along the car on the ground, unless the native slope term is
	; off (G($F791)) or a flight holds its pitch
	tst.w HS_CONTACT(a0)
	beq.s .external
	tst.b -$86f(a4)
	bne.s .external
	movea.l _handling_flight(pc),a1
	tst.w (a1)
	bne.s .external
	move.w -$6bb4(a4),d0		; pitch sine, Q14
	muls.w #HE_WEIGHT,d0
	moveq #14,d2
	asr.l d2,d0
	add.w d0,d1
.external:
	move.w d1,HS_FEXT(a0)
	rts
; D0 = new engine speed, clamped and stored
.engine_speed:
	tst.l d0
	bpl.s .we_low
	moveq #0,d0
.we_low:
	cmpi.l #HE_WE_MAX,d0
	ble.s .we_high
	move.l #HE_WE_MAX,d0
.we_high:
	move.l d0,HS_WE(a0)
	rts
; A1 = the row's entry, D5 = the column's remainder: D0 = the torque
.lerp:
	move.w 2(a1),d0
	sub.w (a1),d0
	muls.w d5,d0
	divs.w #999,d0
	add.w (a1),d0
	rts

; A0 = state, after a call's steps. The speedometer and the native target
; speed from the ground speed, for BA8A; the RPM, which a current phase
; solver keeps as a whole number so its phase steps leave it alone.
; Clobbers D0-D1/A1.
_handling_publish:
	move.l HS_DU(a0),d0
	swap d0
	add.w HS_UBASE(a0),d0
	bpl.s .u_abs
	neg.w d0
.u_abs:
	move.w d0,d1
	mulu.w #HE_K_MPH,d0
	swap d0
	move.w d0,HS_MPH(a0)
	move.w d0,-$66d4(a4)		; G($992C)
	mulu.w #HANDLING_K_PH,d1
	swap d1
	move.w d1,HS_TARGET(a0)
	move.l HS_WE(a0),d0
	moveq #12,d1
	lsr.l d1,d0
	mulu.w #HE_K_RPM,d0
	swap d0
	cmpi.w #HE_RPM_MAX,d0
	bls.s .rpm
	move.w #HE_RPM_MAX,d0
.rpm:
	move.w d0,-$66d6(a4)		; G($992A)
	tst.b HS_PHASE(a0)
	beq.s .done
	lea _phase_state(pc),a1
	swap d0
	clr.w d0
	move.l d0,PH_CURRENT_R(a1)
	move.l d0,PH_ANCHOR_R(a1)
.done:
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
	move.w d3,-(a7)
	move.w HS_NF(a0),d6
	lea _handling_front(pc),a2
	bsr _handling_axle
	move.w (a7)+,d5
	; front force in body axes. The rear wheels get fx less the front
	; wheel's own longitudinal force: fx is the native drive, and the drag
	; of the steered front tyre is the model's (handling_fx fx_total=False).
	; While braking they get fx less the brake torque: the brake is on the
	; front only, and what a front tyre past its limit cannot take is lost,
	; not passed to the rear tyres, which would let go in a fast corner.
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
	; with the drivetrain the rear wheels get its torque
	tst.b HS_ENGINE(a0)
	beq.s .rt_fx
	move.w HS_TREAR(a0),d7
	bra.s .rt_axle
.rt_fx:
	move.w HS_FX(a0),d0
	ext.l d0
	tst.w HS_BRAKE(a0)
	beq.s .rt_drive
	move.w d5,d4
	ext.l d4
.rt_drive:
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
.rt_axle:
	move.w HS_U(a0),d4
	move.w HS_VCR(a0),d5
	move.w HS_NR(a0),d6
	lea HS_REAR(a0),a1
	lea _handling_rear(pc),a2
	bsr _handling_axle
	move.w d1,HS_FYR(a0)
	; forward speed beyond fx: the tyres' deviation from it, and v r;
	; with the drivetrain the tyres' force less drag and gravity
	add.w HS_FXBF(a0),d0
	tst.b HS_ENGINE(a0)
	beq.s .du_fx
	move.w d0,HS_FXT(a0)
	sub.w HS_FEXT(a0),d0
	bra.s .du_v
.du_fx:
	sub.w HS_FX(a0),d0
.du_v:
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

; The arcade's engine torque, lb ft ($7529F0, grass $753170): rows for
; throttle 0, 1/9 .. 1, columns for 0, 1000 .. 11000 rpm
_handling_torque:
	dc.w 75,-10,-30,-50,-70,-80,-80,-80,-80,-80,-80,-80
	dc.w 75,100,1,-12,-29,-41,-49,-60,-71,-76,-78,-80
	dc.w 75,150,32,26,12,-2,-18,-40,-62,-71,-76,-80
	dc.w 75,150,63,63,53,37,13,-20,-53,-67,-73,-80
	dc.w 75,150,94,101,94,76,44,0,-44,-62,-71,-80
	dc.w 75,175,126,139,136,114,76,20,-36,-58,-69,-80
	dc.w 75,175,157,177,177,153,107,40,-27,-53,-67,-80
	dc.w 75,175,188,214,218,192,138,60,-18,-49,-64,-80
	dc.w 75,177,219,252,259,231,169,80,-9,-44,-62,-80
	dc.w 75,200,250,290,300,270,200,100,0,-40,-60,-80
_handling_torque_grass:
	dc.w 75,-10,-30,-30,-40,-40,-40,-40,-40,-40,-40,-40
	dc.w 75,100,1,-12,-29,-41,-40,-40,-40,-40,-40,-40
	dc.w 75,150,60,26,12,-2,-18,-40,-40,-40,-40,-40
	dc.w 75,150,94,63,53,37,13,-10,-40,-40,-40,-40
	dc.w 75,150,94,101,94,76,44,0,-40,-40,-40,-40
	dc.w 75,150,94,101,94,76,44,0,-40,-40,-40,-40
	dc.w 75,150,94,101,150,76,44,0,-40,-40,-40,-40
	dc.w 75,150,150,150,150,76,44,0,-40,-40,-40,-40
	dc.w 75,150,150,150,150,76,44,0,-40,-40,-40,-40
	dc.w 75,150,150,150,150,76,44,0,-40,-40,-40,-40
; Torque factors by gear (neutral, 1-4), Q12: 1.2, 1.25 and 1.3 times 0.925
; in 1st-3rd and 1.3 in top, as the arcade's C1a run shows them; on grass
; 1.1, times 0.925 in 1st-3rd
_handling_factor: dc.w 5325,4547,4736,4925,5325
	dc.w 4506,4168,4168,4168,4506
; Overall ratios (gear times final drive 3.5), Q10
_handling_ratio: dc.w 0,8602,6093,4480,3405
; Locked clutch: the share of the wheel torque left with the engine's
; inertia (0.4 ratio^2) beside the wheel's (10) and the car's (109.47), Q15
_handling_inertia: dc.w 32767,26506,29296,30795,31598
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
