
	INCDIR	Include:
	INCLUDE	whdload.i
	INCLUDE	whdmacros.i

	IFD C_SIMULATION
C_STEP_BUILD = 1
C_RUNTIME_ONLY = 1
STEP_NO_HASH = 1
	ELSE
	IFD VERIFY
	IFD VERIFY_C_STEP
C_STEP_BUILD = 1
	ENDC
	ELSE
C_STEP_BUILD = 1
C_RUNTIME_ONLY = 1
STEP_NO_HASH = 1
	ENDC
	ENDC

; The enhanced runtime uses an optional WHDLoad-managed Fast RAM stack.
; Keep the legacy diagnostic define as an explicit test-build opt-in.
	IFD VERIFY_C_FAST_STACK
C_FAST_STACK = 1
	ENDC
	IFD C_RUNTIME_ONLY
	IFND C_FAST_STACK
C_FAST_STACK = 1
	ENDC
	ENDC

; Runtime projection executes from the already-verified Fast RAM slave hunk.
; Full snapshot diagnostics opt in explicitly for reference comparisons.
	IFD VERIFY_C_OBJECT_FAST
C_OBJECT_FAST = 1
	ENDC
	IFD C_RUNTIME_ONLY
	IFND C_OBJECT_FAST
C_OBJECT_FAST = 1
	ENDC
	ENDC

; Enable caches only after enhanced hardware selection. Preserve the explicit
; diagnostic alias so older reference builds remain reproducible.
	IFD VERIFY_C_CACHE
C_CACHE = 1
	ENDC
	IFD C_RUNTIME_ONLY
	IFND C_CACHE
C_CACHE = 1
	ENDC
	ENDC

; Normalize steering for the one-field runtime. Snapshot diagnostics retain
; explicit selection so older timing references can still be reproduced.
	IFD VERIFY_C_STEERING
C_STEERING = 1
	ENDC
	IFD C_RUNTIME_ONLY
	IFND C_STEERING
C_STEERING = 1
	ENDC
	ENDC

; Predict only the displayed rider heading through the measured render
; interval. Explicit diagnostic selection retains fixed-horizon controls.
	IFD VERIFY_C_POSE_PREDICT
C_POSE_PREDICT = 1
	ENDC
	IFD C_RUNTIME_ONLY
	IFND C_POSE_PREDICT
C_POSE_PREDICT = 1
	ENDC
	IFND VERIFY_C_POSE_PREDICT
	IFND POSE_PREDICT_MEASURED
POSE_PREDICT_MEASURED = 1
	ENDC
	ENDC
	ENDC

	IFD VERIFY_C_GEOMETRY_LUT
	IFND C_STEP_BUILD
	FAIL "Geometry lookup requires VERIFY and VERIFY_C_STEP"
	ENDC
	IFND C_FAST_STACK
	FAIL "Geometry lookup requires the optional expansion allocation"
	ENDC
	ENDC

	IFD BARFLY
	OUTPUT	"RoadRash.Slave"
	BOPT	O+				;enable optimizing
	BOPT	OG+				;enable optimizing
	BOPT	ODd-				;disable mul optimizing
	BOPT	ODe-				;disable mul optimizing
	BOPT	w4-				;disable 64k warnings
	SUPER
	ENDC

;DEBUG
;FILERIP
;BW

;============================================================================

_base		SLAVE_HEADER			;ws_Security + ws_ID
	IFND DEBUG
		dc.w	17			;ws_Version (conditional patches need WHDLoad 17.2)
	ELSE
		dc.w	18			;ws_Version
	ENDC
		dc.w	WHDLF_NoError|WHDLF_ClearMem|WHDLF_EmulTrap|WHDLF_EmulDivZero;ws_flags
		dc.l	$100000			;ws_BaseMemSize
		dc.l	0			;ws_ExecInstall
		dc.w	Start-_base		;ws_GameLoader
		dc.w	_data-_base		;ws_CurrentDir
		dc.w	0			;ws_DontCache
_keydebug	dc.b	0			;ws_keydebug = F9
_keyexit	dc.b	$5F;ws_keyexit = help
_expmem
	IFD C_STEP_BUILD
	IFD C_FAST_STACK
	IFD VERIFY_C_GEOMETRY_LUT
	dc.l -$a000 ; stack plus exact road-width quotient table
	ELSE
	dc.l -$5000 ; optional WHDLoad-managed stack and guards
	ENDC
	ELSE
	dc.l 0
	ENDC
	ELSE
	dc.l 0
	ENDC				;ws_ExpMem
		dc.w	_name-_base		;ws_name
		dc.w	_copy-_base		;ws_copy
		dc.w	_info-_base		;ws_info
		dc.w	0			;ws_kickname
		dc.l	0			;ws_kicksize
		dc.w	0			;ws_kickcrc
		dc.w	_config-_base		;ws_config

;============================================================================

	IFD BARFLY
	DOSCMD	"WDate  >T:date"
	ENDC
DECL_VERSION:MACRO
	dc.b	"2.1 beta"
	IFD BARFLY
		dc.b	" "
		INCBIN	"T:date"
	ENDC
	IFD	DATETIME
		dc.b	" "
		incbin	datetime
	ENDC
	ENDM

_name		dc.b	"Road Rash",0
_copy		dc.b	"1992 Electronic Arts",0
_info		dc.b	"Adapted by JOTD",10,10
		dc.b	"Version "
		DECL_VERSION
		dc.b	0

_data		dc.b	"data",0
_config
	dc.b	"C1:L:password:none,level 1 Diablo 1000 big money,Millions of dollars and level 4,"
	dc.b	"PANDA 600,BANZAI 750,KAMIKAZE 750,SHURIKEN 1000,FERRUCI 850,PANDA 750,DIABLO 1000;"
	
	dc.b	"C2:B:Enhanced framerate;"
	dc.b	0
	EVEN
	include	ReadJoyPad.s
	
;======================================================================
Start	;	A0 = resident loader
;======================================================================

		lea	$7FF00,a7
		MOVE	#$2700,SR
		
		lea	_resload(pc),a1
		move.l	a0,(a1)			;save for later use
		move.l	a0,a2			;A2 = resload
		
		lea	_tags(pc),a0
		jsr	(resload_Control,a2)
	IFD VERIFY
		bsr	verify_start
	ENDC
		
		;get password
		lea	(_user_password,pc),a0
		moveq.l	#0,d1
		move.l	#24,d0
		jsr	(resload_GetCustom,a2)
		
		lea	_boot(pc),a0
		lea	$400.W,a1
		move.l	a1,a3
		jsr	(resload_LoadFileDecrunch,a2)

		lea	_pl_boot(pc),a0
		sub.l	a1,a1
		jsr	(resload_Patch,a2)
		
		move.l	expansion_memory(pc),A0	; expansion start
		move.l	A0,D0	; and size

		jmp	(a3)
		

_pl_boot	PL_START
	PL_P	$496A,PatchLoader2

	; *** patches the 1st disk routine

	PL_P	$4DCA,ReadSomeFile

	; *** patches some exec shit
;;	PATCHUSRJMP	$12BA4,MoveD0_1

	; *** patches a prog

	PL_PS	$4800,PatchIntro1

	; *** patches another prog

	PL_PS	$4844,PatchIntro2
	PL_END

PatchIntro1:
	; fixes execbase access (maybe for protection...)
	movem.l	d0-d1/a1-a2,-(a7)
	lea	pl_intro_1(pc),a0
	sub.l	a1,a1
	move.l	_resload(pc),a2
	jsr	(resload_Patch,a2)
	movem.l	(a7)+,d0-d1/a1-a2

	move.l	$4C98.W,A0
	rts
	
pl_intro_1:
	PL_START
	PL_R	$12BAE
	PL_END
	
PatchIntro2:
	movem.l	d0-d1/a1-a2,-(a7)
	lea	pl_intro_2(pc),a0
	sub.l	a1,a1
	move.l	_resload(pc),a2
	jsr	(resload_Patch,a2)
	movem.l	(a7)+,d0-d1/a1-a2
	
	move.l	$4C98.W,A0
	rts
	
pl_intro_2:
	PL_START
	PL_P	$8E58,ReadSomeFile
	PL_P	$8CDA,MoveD0_2
	PL_END


	
;MoveD0_1:
;	move.w	#$FC77,D0
;	rts

MoveD0_2:
	move.w	#$395,D0
	rts
	
last_key_pressed_offset = $2e969
keytable_offset = $2E868

PatchLoader2:
	; detect controllers now, leaving time for the user
	; to plug proper pads
	move.l	expansion_memory(pc),a1

	movem.l	d0-d1/a0-a2,-(a7)
	add.l	#$580,a1
	move.w	#24,D1
	bsr	_detect_controller_types
	lea	_user_password(pc),a0
	tst.b	(a0)
	beq.b	.no_user_password
	subq	#1,d1
.copy_user
	move.b	(a0)+,(a1)+
	dbf	d1,.copy_user
	bsr	.custom_pass
	bra.b	.nopass
.no_user_password	
	move.l	_password(pc),d0
	beq.b	.nopass
	lea	password_data(pc),a0
	subq.l	#1,d0
	mulu.w	d1,D0
	subq.l	#1,d1

	add.l	d0,a0
	cmp.l	password_data_end(pc),a0
	bcc.b	.nopass	; out of range
.copy
	move.b	(a0)+,(a1)+
	dbf	d1,.copy
	bsr	.custom_pass
.nopass
	; change messages if joypad is plugged in
	move.l	expansion_memory(pc),a1
	lea	pl_main(pc),a0
	move.b	controller_joypad_1(pc),d0
	beq.b	.nopad
	lea	pl_messages_main(pc),a0	
.nopad
	move.l	_resload(pc),a2
	jsr	(resload_Patch,a2)
	IFD C_STEP_BUILD
	bsr	step_select_path
	tst.l	d0
	beq.b	.no_c
	IFD C_CACHE
; WHDLoad honors NoCache and flushes after SetCPU. BaseMem is write-through,
; never copyback; preserve the existing ExpMem and slave cacheability.
	move.l #WCPUF_Base_WT|WCPUF_IC|WCPUF_DC,d0
	move.l #WCPUF_Base|WCPUF_IC|WCPUF_DC,d1
	move.l _resload(pc),a2
	jsr (resload_SetCPU,a2)
	ENDC
	move.l	expansion_memory(pc),a1
	lea	pl_c_simulation(pc),a0
	move.l	_resload(pc),a2
	jsr	(resload_Patch,a2)
	IFD C_OBJECT_FAST
	bsr step_object_fast_init
	ENDC
	IFD VERIFY_C_ROAD_FAST
	bsr step_road_fast_init
	ENDC
.no_c:
	ENDC
	movem.l	(a7)+,d0-d1/a0-a2
	jmp	(a1)
	
.custom_pass
	move.l	expansion_memory(pc),a1
	lea	pl_password(pc),a0
	move.l	_resload(pc),a2
	jsr	(resload_Patch,a2)
	rts
	
	; skip copy default password so we can install passwords
pl_password
	PL_START
	PL_S	$22E,$36-$2E
	PL_END
	
	; change function keys by pad buttons
pl_messages_main
	PL_START
	PL_STR	$2B3F,<rev for >
	PL_STR	$2B81,<fwd to turn >
	PL_STR	$2BC7,<blue>
	PL_STR	$2C30,<green to select >
	PL_STR	$2C74,<yellow to>
	PL_STR	$2CB9,<rev+fwd during>
	PL_STR	$2F45,<blue>
	PL_STR	$2FCB,<fwd to check >
	PL_STR	$303A,<blue>
	PL_STR	$2537,<Press blue to >
	; *** install joypad handler for menu
	; pretty useless for joystick only
	; on the other hand, with joypad, we can get rid
	; of keyboard!
	PL_PSS	$52,menu_control_loop,4

	PL_NEXT	pl_main
	

pl_main
	PL_START
	PL_IFC2
	IFD VERIFY_C_SEED_RNG
	PL_PS $657C,step_seed_rng
	ENDC
	IFND C_STEP_BUILD
	PL_PS	$7736,safe_swap
	PL_PS	$6FA0,bound_delta
	PL_PS	$9D32,field_animation
	ENDC
	PL_ENDIF
	IFD VERIFY
	PL_PS	$6FE0,verify_field
	PL_PS	$71DC,verify_frame
	IFD VERIFY_B
	PL_PS	$75BC,verify_b_gate
	PL_PS	$AFF0,verify_b_drain
	ENDC
	IFND C_STEP_BUILD
	PL_IFC2
	IFD VERIFY_SKIP_RENDER
	PL_NOP	$7730,6
	ENDC
	IFD VERIFY_FRAME_PERIOD
	PL_PS	$7736,verify_pace
	ENDC
	PL_ENDIF
	ENDC
	IFD VERIFY_C_AUDIT
	PL_PSS	$747E,verify_c_sim_begin,2
	PL_PS	$75B6,verify_c_render_begin
	PL_P	$7748,verify_c_render_end
	ENDC
	ENDC

	
	; *** pause
	PL_PSS	$72B4,test_for_pause,2
	
	; *** removes password protection
	PL_L	$331A4,$600000A8   ; no check for correct answer
	PL_NOP	$3319C,2	   		; no need to press return

	; *** sets the kbint patch

	PL_PS	$2E9D8,kbint

	; *** patches the 2nd disk routine

	PL_P	$2DF82,ReadSomeFile

	; *** remove the 'insert disk 2'
	PL_NOP	$2F116,2
	PL_END
	

	IFD C_STEP_BUILD
pl_c_simulation
	PL_START
	PL_IFC2
	PL_PSS $660E,step_prepare,2
	PL_P	$747E,step_main
	PL_P	$75B6,step_end
	PL_P	$915A,step_camera_decay
	IFD STEP_EXTRAPOLATE
	PL_PS	$75C8,step_view_begin
	PL_P	$7748,step_view_end
	ENDC
	PL_NOP	$76C6,6
	PL_PSS	$A40E,step_start_sprite,2
	PL_PS	$70DC,step_field_input
	PL_S	$70E2,$7116-$70E2
	PL_P	$73F4,step_input_key
	PL_PSS	$9E0E,step_crash_sprite,2
	PL_PS	$9E26,step_pose_clear
	PL_NOP	$9D24,6
	PL_NOP	$9D32,6
	PL_PS	$A104,step_spark_test
	PL_NOP	$A11C,6
	PL_NOP	$9EEC,4
	PL_P	$9E70,step_pose_lean
	PL_P	$9EF0,step_lean_end
	PL_P	$9F48,step_pose_project
	IFD VERIFY_C_ROAD_FAST
	PL_P $970E,step_road_fast_code
	ENDC
	IFD C_OBJECT_FAST
	PL_P $B02E,step_object_fast_code
	ENDC
	IFD VERIFY_C_OBJECT_WIDTH
; Width is not consumed by rejection tests. Defer the divide until the
; object's depth/lateral checks have accepted it.
	PL_NOP $B2E8,6
	PL_PSS $B326,step_object_width,2
	ENDC
	IFD C_STEERING
	PL_P	$B93A,step_steering_heading
	PL_P	$B97A,step_steering_motion
	PL_P	$B9A0,step_steering_store
	ENDC
	IFD C_POSE_PREDICT
	PL_PSS $A8E2,step_predict_pose,4
	IFD POSE_PREDICT_MEASURED
	IFD STEP_EXTRAPOLATE
	FAIL "Measured pose prediction conflicts with whole-view extrapolation"
	ENDC
	IFD VERIFY_C_LATENCY
	FAIL "Measured pose prediction conflicts with the latency probe"
	ENDC
	PL_PS $75C8,step_predict_render_begin
	PL_PS $773C,step_predict_render_end
	ENDC
	ENDC
	PL_S	$AECC,$AEE2-$AECC
	PL_NOP	$6FA0,6
	PL_R	$6FE6
	PL_NOP	$28C7C,$28C94-$28C7C
	PL_NOP	$28C9A,$28CBC-$28C9A
	PL_PSS	$28C4C,step_reset,4
	IFD VERIFY_SKIP_RENDER
	PL_NOP	$7730,6
	ENDC
	IFD VERIFY_FRAME_PERIOD
	PL_PS	$7736,verify_pace
	ENDC
	IFD VERIFY_C_LATENCY
	PL_PS	$75C8,step_latency_render
	PL_PS	$7736,step_latency_swap
	ENDC
	IFD VERIFY_C_EVENTS
	PL_PS $F06A,step_event_engine
	PL_PS $F080,step_event_stop
	PL_PS $F0BE,step_event_primary
	PL_PS $F0DE,step_event_secondary
	PL_PS $F120,step_event_siren
	ENDC
	IFD C_FAST_STACK
	PL_P	$2876C,step_stack_start
	ENDC
	PL_ENDIF
	PL_END
	ENDC

	IFD VERIFY_C_SEED_RNG
	IFND VERIFY
	FAIL "Fixed RNG seed is diagnostic only"
	ENDC
; Shared by diagnostic B references and C. Seed before native actor creation,
; so menu frame count cannot select different initial opponent randomness.
step_seed_rng:
	move.l d0,-(a7)
	moveq #0,d0
	jsr $90088
	jsr $9011c
	move.l (a7)+,d0
	jmp $8685c
	ENDC

; A one-field simulation has measurable integration/collision differences.
; Wait for one elapsed tick; the original swap waits for the following tick.
safe_swap:
	cmpi.b	#1,$aec0c
	bcs.b	safe_swap
	jmp	$aecba

; Bound unusually long frames before both physics and rate calculations use d1.
bound_delta:
	cmpi.w	#8,d1
	bls.b	.store
	moveq	#8,d1
.store:
	move.w	d1,$a6f00
	rts

; Four fields per phase, independent of rendered frame rate. The original
; ANDI.B #7 at $89d38 retains the wrap and the original condition codes.
field_animation:
	move.l	d0,-(a7)
	move.l	$a5d4c,d0
	IFD VERIFY
	movem.l	a0,-(a7)
	lea	verify_animation(pc),a0
	move.l	d0,8(a0)
	ENDC
	lsr.l	#2,d0
	move.b	d0,$a5990
	IFD VERIFY
	and.l	#7,d0
	move.l	d0,12(a0)
	movem.l	(a7)+,a0
	ENDC
	; Original ADDQ on a phase in 0..7 always clears X; ANDI preserves X.
	andi	#$ef,ccr
	move.l	(a7)+,d0
	rts
	IFD VERIFY
verify_animation:
	dc.b	'RRANIM01'
	dc.l	0,0
	ENDC

FUNCTION_KEYPRESS:MACRO
	btst	#JPB_BTN_\1,d0
	beq.b	.no\1
	st.b	(\2,a0)
	bra.b	.out\1
.no\1
	clr.b	(\2,a0)
.out\1
	ENDM
	
test_for_pause
	movem.l	d0-d1/a0,-(a7)
	move.l	expansion_memory(pc),a0
	add.l	#last_key_pressed_offset,a0
	
	moveq.l	#1,d0
	bsr	_read_joystick
	btst	#JPB_BTN_PLAY,d0
	beq.b	.nopause
	move.B	#$40,(a0)		;072b4: 0c3900400002e969
.wr
	bsr	_read_joystick
	btst	#JPB_BTN_PLAY,d0
	bne.b	.wr
	
.nopause
	; Compare while a0 still addresses the key; MOVEM preserves the flags.
	cmpi.b	#$40,(a0)		; original cmpi.b #$40,$ae969
	movem.l	(a7)+,d0-d1/a0
	rts
	
menu_control_loop:
	BTST	#3,D1			;00052: 08010003
	BEQ.S	.out		;00056: 6704
	ORI.B	#$08,D0			;00058: 00000008
.out
	movem.l	d0-d3/a0-a2,-(a7)
	move.l	expansion_memory(pc),a2
	add.l	#last_key_pressed_offset,a2
	move.l	previous_button_state(pc),d3
	lea	backflag(pc),a0
	tst.b	(a0)
	beq.b	.noback
	subq.b	#1,(a0)
	bne.b	.noback

	move.b	#$4F,(a2)
	move.l	d3,d0
	bra	.noprevletter
.noback
	lea	keytable_offset,a0
	add.l	expansion_memory(pc),a0
	moveq.l	#1,d0
	bsr	_read_joystick
	FUNCTION_KEYPRESS	REVERSE,$50
	FUNCTION_KEYPRESS	FORWARD,$51
	FUNCTION_KEYPRESS	BLU,$52
	FUNCTION_KEYPRESS	GRN,$53
	FUNCTION_KEYPRESS	YEL,$54
	
	btst	#JPB_BTN_REVERSE,d0
	beq.b	.nof10
	btst	#JPB_BTN_FORWARD,d0
	beq.b	.nof10
	st.b	($59,a0)
	bra.b	.f10p
.nof10
	clr.b	($59,a0)
.f10p

	; cursor keys emulated by joystick
	btst	#JPB_BTN_UP,d0
	beq.b	.noup
	move.b	#$4C,(a2)
.noup
	btst	#JPB_BTN_DOWN,d0
	beq.b	.nodown
	move.b	#$4D,(a2)
.nodown
	btst	#JPB_BTN_LEFT,d0
	beq.b	.noleft
	move.b	#$4F,(a2)
.noleft
	btst	#JPB_BTN_RIGHT,d0
	beq.b	.noright
	move.b	#$4E,(a2)
.noright
	lea	current_pos(pc),a0
	lea	raw_table(pc),a1
	moveq	#0,d1
	
	btst	#JPB_BTN_FORWARD,d3
	bne.b	.nonextletter		; was pressed
	btst	#JPB_BTN_FORWARD,d0
	beq.b	.nonextletter

	addq.b	#1,(a0)
	move.b	(a0),d1
	tst.b	(a1,d1.w)
	bpl.b	.nofwrap
	clr.b	(a0)
	moveq	#0,d1
.nofwrap
	move.b	(a1,d1.W),(a2)
	bsr	.nexttimeback
.nonextletter
	btst	#JPB_BTN_REVERSE,d3
	bne.b	.noprevletter		; was pressed
	btst	#JPB_BTN_REVERSE,d0
	beq.b	.noprevletter

	; back one character
	tst.b	(a0)
	bne.b	.nofirst	; first count
.gotolast
	move.b	(a0),d1
	addq.b	#1,(a0)
	tst.b	(a1,d1.W)
	bpl.b	.gotolast
	subq.b	#1,(a0)
.nofirst
	subq.b	#1,(a0)
	move.b	(a0),d1
	move.b	(a1,d1.W),(a2)
	bsr	.nexttimeback
.noprevletter

	lea	previous_button_state(pc),a0
	move.l	d0,(a0)

	movem.l	(a7)+,d0-d3/a0-a2
	rts
.nexttimeback
	lea	backflag(pc),a0
	move.b	#2,(a0)
	rts

	
kbint:
	move.b	$BFEC01,D0
	move.l	D0,-(sp)
	ror.b	#1,D0
	not.b	D0
	
	cmp.b	_keyexit(pc),D0
	bne	.noquit
	pea	TDREASON_OK
	move.l	_resload(pc),-(a7)
	addq.l	#resload_Abort,(a7)
	rts
.noquit
	move.l	(sp)+,D0
	rts	

password_data:
	dc.b	"00000  REDC0QNGM5  172SU"
    dc.b    "00000  01O00MTPN8  4NPBI"   ;To give millions of $ and level 4
    dc.b	"00000  00J00102VS  21JUD"   ;PANDA 600
    dc.b	"00000  00J01113BT  22KDP"   ;BANZAI 750
 ;       "00000 00R00 013VS 32RV4"   BANZAI 750
    dc.b	"00000  00S20117H5  33UV1"   ;KAMIKAZE 750
    dc.b	"00000  01421109G5  448VN"   ;SHURIKEN 1000
    dc.b	"00000  01420019G5  457VO"   ;FERRUCI 850
    dc.b	"00000  01S91OOEGJ  567HM"   ;PANDA 750
    dc.b	"00000  01S9010EGJ  576IK"   ;DIABLO 1000
password_data_end



; < A0: filename
; < A1: destination address
; > D0: 0 (ok)
; > D1: filesize (not returning that leads to strange bugs...)

ReadSomeFile:
	; Preloaded files can arrive before the previous screen blit finishes.
	; Finish DMA before overwriting its destination (notably DASH2.LBM).
	tst.b	$dff002
.wait_blitter
	btst	#6,$dff002
	bne.b	.wait_blitter
	movem.l	a0-a2,-(sp)

	cmp.b	#':',3(A0)	; does the name mention xxx: ??
	bne	.skipdf0
	lea	$4(A0),A0	; skips 'DF0:'
	tst.b	(A0)
	beq	.exit

.skipdf0
	cmp.b	#'/',4(A0)	; does the name mention data/ ??
	bne	.skipdata
	lea	$5(A0),A0	; skips 'data/'

	movem.l	a1,-(a7)
	lea	locpla_name(pc),A1
	bsr	strcmp
	movem.l	(a7)+,a1
	tst.l	D0
	bne	.skipdata

	; *** trick to wait a bit during the fading
	; *** else the colors are fucked up

	move.l	#20000,D0
	bsr		beamdelay

.skipdata
	
	tst.b	(A0)		; end of file
	beq	.exit

	move.l	_resload(pc),a2
	movem.l	a0,-(a7)
	jsr	(resload_LoadFile,a2)
	movem.l	(a7)+,a0
	jsr	(resload_GetFileSize,a2)
	move.l	d0,d1
.exit
	moveq	#0,D0		; no problemo
	movem.l	(sp)+,a0-a2
	rts


; < D0: numbers of vertical positions to wait
beamdelay
.bd_loop1
	move.w  d0,-(a7)
    move.b	$dff006,d0	; VPOS
.bd_loop2
	cmp.b	$dff006,d0
	beq.s	.bd_loop2
	move.w	(a7)+,d0
	dbf	d0,.bd_loop1
	rts
	
; < a0: str1
; < a1: str2
; > d0: -1: fail, 0: ok

strcmp:
	movem.l	d1/a0-a1,-(A7)
.contstrcmpasm
	move.b	(A0)+,d0
	beq.s	.termstrcmpasm
	move.b	(A1)+,d1
	beq.s	.failstrcmpasm
	bsr.s	.letterstrcmpasm
	exg	d0,d1
	bsr.s	.letterstrcmpasm
	cmp.b	d0,d1
	bne.s	.failstrcmpasm
	bra.s	.contstrcmpasm

.termstrcmpasm
	tst.b	(A1)+
	bne.s	.failstrcmpasm
	moveq.l	#0,d0
	bra.s	.endstrcmpasm

.letterstrcmpasm
	cmp.b	#$60,d0
	bls.s	.letter1strcmpasm
	cmp.b	#$7a,d0
	bhi.s	.letter1strcmpasm
	sub.b	#$20,d0
.letter1strcmpasm
	rts

.failstrcmpasm
	moveq.l	#-1,d0
.endstrcmpasm
	movem.l	(A7)+,d1/a0-a1
	rts

current_pos:
	dc.b	0
backflag:
	dc.b	0
raw_table:
 	dc.b	$40	; space 
 	dc.b	$0A ; 0
 	dc.b	$01 ; 1
 	dc.b	$02 ; 2
 	dc.b	$03 ; 3
 	dc.b	$04 ; 4
 	dc.b	$05 ; 5
 	dc.b	$06 ; 6
 	dc.b	$07 ; 7
 	dc.b	$08 ; 8
 	dc.b	$09 ; 9
 	dc.b	$20	; A
 	dc.b	$35 ; B
 	dc.b	$33 ; C
 	dc.b	$22	; D
 	dc.b	$12	; E
 	dc.b	$23	; F
 	dc.b	$24	; G
 	dc.b	$25	; H
 	dc.b	$17	; I
 	dc.b	$26 ; J
 	dc.b	$27 ; K
 	dc.b	$28 ; L
 	dc.b	$37 ; M
 	dc.b	$36 ; N
 	dc.b	$18	; O
 	dc.b	$19	; P
 	dc.b	$10	; Q
 	dc.b	$13	; R
 	dc.b	$21	; S
 	dc.b	$14	; T
 	dc.b	$16	; U
 	dc.b	$34 ; V
 	dc.b	$11	; W
  	dc.b	$32 ; X
	dc.b	$15	; Y
 	dc.b	$31 ; Z
 	;dc.b	$39 ; .
 	;dc.b	$2A	; '
	dc.b	$FF
	

;======================================================================
_user_password:
	ds.b	26
_boot:
	dc.b	"lomain.ami",0
locpla_name:
	dc.b	"locpla.set",0
	cnop	0,4
_resload	dc.l	0		;address of resident loader
_tags
		dc.l	WHDLTAG_CUSTOM1_GET
_password		dc.l	0
	dc.l	WHDLTAG_CUSTOM2_GET
_enhanced_framerate	dc.l	0
	IFD C_STEP_BUILD
	dc.l WHDLTAG_ATTNFLAGS_GET
verify_attn dc.l 0
	ELSE
	IFD VERIFY
	dc.l WHDLTAG_ATTNFLAGS_GET
verify_attn dc.l 0
	ENDC
	ENDC
	dc.l	0
	
previous_button_state
	dc.l	0
expansion_memory:
	dc.l	$80000
	IFD VERIFY
	include	verify.s
	IFD VERIFY_B
	include	verify_b.s
	ENDC
	IFD VERIFY_C_AUDIT
	include	verify_c_audit.s
	ENDC
	ENDC
	
	IFD C_STEP_BUILD
	IFND VERIFY
verify_c_selection:
	dc.b "RRCSEL01"
	dc.l 0,0,0,0
	ENDC
	include simulation.s
	ENDC
	IFD DEBUG
		dc.l	WHDLTAG_CUST_DISABLE,vposw
		dc.l	WHDLTAG_CUST_DISABLE,vhposw
	;	dc.l	WHDLTAG_CUST_DISABLE,copjmp1
	;	dc.l	WHDLTAG_CUST_DISABLE,copjmp2
	ENDC
		dc.l	0
