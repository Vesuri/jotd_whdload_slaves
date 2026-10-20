; Diagnostic C proof, enabled only by VERIFY + VERIFY_C_STEP.
; Diagnostic experiments require CUSTOM2=1 (Enhanced framerate).
; STEP_FIELDS=1 (50 Hz PAL) is the primary candidate. STEP_EXTRAPOLATE is
; an optional experiment for larger diagnostic quanta, never a frame-rate mode.
; No overflow recovery or complete
; pause/transition/action audit yet. See simulation-timing.md before extending.
; All game addresses below are absolute. Normal builds contain none of this.
;
; RRCSTEP1: cursor +8, count +12, captured field +16, quantum +20,
; frozen $a5900..$a873f at +24. RRCHASH2 follows with a longword slot count and actor
; hashes (slot zero unused). Copies/hashes perturb timing: no FPS claims.

; Select only if enabled, CPU >= 020, and the allocated public slave hunk is
; in a conventional Fast RAM window. Do not mistake Chip or $c00000 slow RAM
; for Fast RAM. Reject the whole reserved upper-24-bit window conservatively.
; No probing of unallocated addresses or extra allocation is needed.
; Reason: 0 disabled, 1 CPU, 2 memory placement, 3 selected. Return d0=0/1.
step_select_path:
	lea verify_c_selection+8(pc),a0
	move.l _enhanced_framerate(pc),d0
	move.l d0,(a0)+
	move.l verify_attn(pc),d1
	move.l d1,(a0)+
	lea _base(pc),a1
	move.l a1,(a0)+
	clr.l (a0)
	tst.l d0
	beq .no
	move.l #1,(a0)
	btst #1,d1
	beq .no
	move.l #2,(a0)
	cmpa.l #$200000,a1
	bcs .no
	cmpa.l #$a00000,a1
	bcs .yes
	cmpa.l #$1000000,a1
	bcs .no
.yes:
	move.l #3,(a0)
	moveq #1,d0
	rts
.no:
	moveq #0,d0
	rts

	IFND STEP_HASH_SLOTS
STEP_HASH_SLOTS = 2048
	ENDC
	IFLT STEP_HASH_SLOTS-2
	FAIL "STEP_HASH_SLOTS needs slot zero and at least one tick"
	ENDC
	IFGT STEP_HASH_SLOTS-8192
	FAIL "STEP_HASH_SLOTS exceeds signed indexed addressing"
	ENDC
	IFND STEP_CAPTURE
STEP_CAPTURE = 601
	ENDC
	IFND STEP_FIELDS
STEP_FIELDS = 1
	ENDC
step_reset:
	movem.l d0-d7/a0-a6,-(a7)
	lea step_stats(pc),a0
	move.l $a5d4c,8(a0)
	clr.l 12(a0)
	clr.l 16(a0)
	lea step_queued_field(pc),a1
	move.l $a5d4c,(a1)
	clr.b step_replaying-step_queued_field(a1)
	clr.b step_input_overflow-step_queued_field(a1)
	IFD VERIFY_C_LATENCY
	bsr step_latency_reset
	ENDC
	IFD VERIFY_C_DECAY_TEST
	bsr step_decay_test
	ENDC
	IFD STEP_EXTRAPOLATE
	bsr step_save_previous
	ENDC
	jsr $8f552
	lea step_start_frame(pc),a0
	move.w d0,(a0)
	movem.l (a7)+,d0-d7/a0-a6
	move.l #$87040,$a5916
	rts
; Consume every due step without discarding elapsed-time remainder.
step_main:
	lea step_stats(pc),a0
	move.l 8(a0),d0
	add.l #STEP_FIELDS,d0
	cmp.l $a5d4c,d0
	bhi .render
	bsr step_replay_inputs
	lea step_stats(pc),a0
	move.l 8(a0),d0
	add.l #STEP_FIELDS,d0
	move.l d0,8(a0)
	move.l d0,$a5d50
	addq.l #1,12(a0)
	move.w #STEP_FIELDS,$a6f00
	bsr step_clock
	move.w $a5d1e,d0
	cmp.w $a5d38,d0
	ble .highwater
	move.w d0,$a5d38
.highwater:
	IFD STEP_EXTRAPOLATE
	bsr step_save_previous
	ENDC
	bsr step_collision_objects
	bsr .run
	bra step_main
.run:
	cmpi.w #$20,$a59da
	jmp $87486
.render:
	jmp $875bc
; Run stateful presentation helpers exactly once per simulation step.
step_end:
	jsr $89138
	bsr step_track_events
	bsr step_actor_animations
	bsr step_spark_events
	bsr step_derive_lean
	bsr step_scenery_cursor
	bsr step_pose_events
	jsr $8f552
	lea step_start_frame(pc),a0
	move.w d0,(a0)
	jsr $8eff8
	IFND STEP_NO_HASH
	moveq #0,d0
	lea $a5d60,a0
	move.w #$1180/4-1,d1
.hash:
	rol.l #5,d0
	move.l (a0)+,d2
	eor.l d2,d0
	dbf d1,.hash
	move.l step_stats+12(pc),d1
	cmpi.l #STEP_HASH_SLOTS,d1
	bcc .nohash
	lsl.w #2,d1
	lea step_hashes+12(pc),a0
	move.l d0,(a0,d1.w)
.nohash:
	ENDC
	lea step_stats(pc),a0
	cmpi.l #STEP_CAPTURE,8(a0)
	bne .done
	lea step_snapshot(pc),a1
	lea $a5900,a0
	move.w #($a8740-$a5900)/4-1,d0
.copy:
	move.l (a0)+,(a1)+
	dbf d0,.copy
	lea step_stats(pc),a0
	move.l #STEP_CAPTURE,16(a0)
.done:
	IFD VERIFY_C_LATENCY
	bsr step_latency_simulated
	ENDC
	rts
	cnop 0,4
step_stats:
	dc.b 'RRCSTEP1'
	dc.l 0,0,0,STEP_FIELDS
step_snapshot:
	ds.b $a8740-$a5900

step_hashes:
	dc.b "RRCHASH2"
	dc.l STEP_HASH_SLOTS
	ds.l STEP_HASH_SLOTS

step_start_sprite:
	move.w step_start_frame(pc),d0
	move.w d0,8(a0)
	rts
step_start_frame:
	dc.w 0

; The original reference loses 1/4 of the crash-camera offset per four fields.
; One field retains (3/4)^(1/4): decay coefficient round(65536*(1-root))=4548.
; Actor displacement already includes delta; only the recovery decay needs this.
step_camera_decay:
	move.l $a7c02,d0
	bsr step_decay
	move.l d0,$a7c02
	jmp $891ae

; Signed 32-bit offset in/out d0. Split the product to avoid overflow and retain
; 68000-compatible instructions. Repeat per field for larger diagnostic quanta.
step_decay:
	movem.l d1-d3,-(a7)
	moveq #STEP_FIELDS-1,d3
.field:
	move.l d0,d2
	move.l d0,d1
	swap d1
	muls.w #4548,d1
	mulu.w #4548,d0
	swap d0
	andi.l #$ffff,d0
	add.l d1,d0
	sub.l d0,d2
	move.l d2,d0
	dbf d3,.field
	movem.l (a7)+,d1-d3
	rts

	IFD VERIFY_C_DECAY_TEST
step_decay_test:
	lea step_decay_cases(pc),a0
	lea step_decay_results+8(pc),a1
	moveq #10-1,d4
.next:
	move.l (a0)+,d0
	bsr step_decay
	move.l d0,(a1)+
	dbf d4,.next
	rts
step_decay_cases:
	dc.l $80000000,-65536,-32768,-28672,-1,0,1,32767,65536,$7fffffff
step_decay_results:
	dc.b "RRCDECAY"
	ds.l 10
	ENDC

; Field producer: use existing control/pause handling, but keep the physics
; steering and throttle state owned by the simulation consumer.
; Replace the whole native demo/player dispatch. A hook spanning $8710c..$87115
; is unsafe: the native demo branches land at $87110 inside that replacement.
step_field_input:
	tst.w $a7204
	beq step_queue_input
	addq.w #1,$a7206
	cmpi.w #3600,$a7206
	bmi .poll
	move.w #1,$a59d2
	move.w #1,$a59d0
	bra .done
.poll:
	jsr $87276
.done:
	tst.w $a59d2
	rts

step_queue_input:
	movem.l d3-d6/a0-a1,-(a7)
	move.b $a598c,d6
	move.w $a7262,d3
	move.b $a5dc8,d4
	lea step_replaying(pc),a0
	move.b (a0),d5
	clr.b (a0)
	jsr $87298
	lea step_replaying(pc),a0
	move.b d5,(a0)
	move.w d3,$a7262
	move.b d4,$a5dc8
	move.l $a5d4c,d3
	cmp.l step_queued_field(pc),d3
	beq .done
	move.l d3,d4
	sub.l step_stats+8(pc),d4
	cmpi.l #2048,d4
	bcc .overflow
	andi.w #2047,d3
	lea step_inputs(pc),a0
	move.b $a598c,(a0,d3.w)
	IFD VERIFY_C_LATENCY
	bsr step_latency_input
	ENDC
	lea step_queued_field(pc),a0
	move.l $a5d4c,(a0)
	bra .done
.overflow:
	lea step_input_overflow(pc),a0
	st.b (a0)
.done:
	move.b d6,$a598c
	movem.l (a7)+,d3-d6/a0-a1
	tst.w $a59d2
	rts

step_replay_inputs:
; The demo drives its player through AI. Do not replay an unproduced human queue.
	tst.w $a7204
	bne .done
	move.l step_stats+8(pc),d3
	moveq #STEP_FIELDS-1,d4
	lea step_replaying(pc),a0
	st.b (a0)
.next:
	addq.l #1,d3
	move.w d3,d0
	andi.w #2047,d0
	lea step_inputs(pc),a0
	move.b (a0,d0.w),d0
	move.b d0,$a598c
	tst.b d0
	beq .idle
	jsr $872c0
	bra .applied
.idle:
	jsr $8744c
.applied:
	IFD VERIFY_C_LATENCY
	bsr step_latency_replayed
	ENDC
	dbf d4,.next
	lea step_replaying(pc),a0
	clr.b (a0)
.done:
	rts

step_input_key:
	btst #0,step_replaying(pc)
	bne .replayed
	cmpi.b #$40,$ae969
	jmp $873fc
.replayed:
	rts

	cnop 0,4
step_queued_field:
	dc.l 0
step_replaying:
	dc.b 0
step_input_overflow:
	dc.b 0
step_inputs:
	ds.b 2048

; Cached crash poses let drawing reuse animation without advancing recovery.
step_actor_animations:
	lea $909cc,a2
.next:
	move.l (a2)+,a1
	cmpa.l #-1,a1
	beq .done
	btst #4,$68(a1)
	beq .flash
	cmpa.l #$a5de0,a1
	beq .clear_crash
	tst.b $6e(a1)
	bmi .clear_crash
	jsr $8f190
	move.l a1,d1
	sub.l #$a5d60,d1
	lsr.w #6,d1
	lea step_crash_frames(pc),a0
	move.w d0,(a0,d1.w)
	tst.b $6e(a1)
	bpl .next
.clear_crash:
	bclr #4,$68(a1)
	bra .next
.flash:
	tst.w $12(a1)
	beq .next
	move.b $6a(a1),d0
	btst #2,d0
	beq .next
	andi.b #3,d0
	cmpi.b #2,d0
	bcc .next
	subi.b #STEP_FIELDS,$70(a1)
	bgt .next
	clr.b $70(a1)
	bclr #2,$6a(a1)
	bra .next
.done:
	rts
step_crash_sprite:
	movem.l d1/a0,-(a7)
	move.l a1,d1
	sub.l #$a5d60,d1
	lsr.w #6,d1
	lea step_crash_frames(pc),a0
	move.w (a0,d1.w),d0
	movem.l (a7)+,d1/a0
	tst.b $6e(a1)
	rts
	even
step_crash_frames:
	ds.w 35

; Physics reads actor +$34, so rendering must not overwrite this derived state.
step_derive_lean:
	move.w $a6ef6,-(a7)
	clr.w $a6ef6
	lea step_lean_busy(pc),a0
	st.b (a0)
	lea $909cc,a2
.next:
	move.l (a2)+,a1
	cmpa.l #-1,a1
	bne .actor
	tst.w $a6ef6
	bne .special
	move.w #1,$a6ef6
	lea $941d6,a2
	bra .next
.special:
	cmpi.w #2,$a6ef6
	beq .done
	cmpi.l #1800,$a5d50
	bcs .done
	move.w #2,$a6ef6
	lea $941e2,a2
	bra .next
.actor:
; Match the native $89d64..$89de4 list eligibility checks.
	cmpi.w #1,$a6ef6
	bne .checkspecial
	cmpi.w #-1,$56(a1)
	bne .next
	bra .position
.checkspecial:
	cmpi.w #2,$a6ef6
	bne .position
	btst #6,$68(a1)
	beq .done
	move.l 4(a1),d0
	sub.l $a5d1e,d0
	bmi .done
.position:
	move.w 4(a1),d0
	sub.w $a5d1e,d0
	bmi .next
	cmpi.w #30,d0
	bgt .next
	move.l 4(a1),d2
	jsr $89e70
	bra .next
.done:
	lea step_lean_busy(pc),a0
	clr.b (a0)
	move.w (a7)+,$a6ef6
	rts
step_lean_end:
	btst #0,step_lean_busy(pc)
	bne .computed
	move.w d0,$a(a0)
	tst.w $a6ef6
	jmp $89efa
.computed:
	move.w d2,$34(a1)
	rts
step_lean_busy:
	dc.b 0
	even

step_scenery_cursor:
	move.l $a5d1e,d0
	move.l $a808e,a1
.back:
	cmpa.l #$a8096,a1
	beq .forward
	move.l -4(a1),d1
	clr.w d1
	cmp.l d0,d1
	bcs .forward
	subq.l #4,a1
	bra .back
.forward:
	move.l (a1),d1
	cmpi.l #-1,d1
	beq .done
	clr.w d1
	cmp.l d0,d1
	bcc .done
	addq.l #4,a1
	bra .forward
.done:
	move.l a1,$a808e
	rts

; Rebuild the world-object collision inputs for every step. The original
; collision code reads these projection records, not just world positions.
step_collision_objects:
	jsr $8970e
	clr.w $a8734
	clr.w $a59fc
	jsr $8b02e
	move.w $a8734,$a59fe
	jsr $8a492
	rts

; The live field clock schedules work; the race stopwatch belongs to simulation.
; Preserve the original game's 60-field BCD second, including its finish flag.
step_clock:
	btst #7,$a5dc8
	bne .done
	moveq #STEP_FIELDS-1,d3
.next:
	addq.w #1,$a5d58
	cmpi.w #60,$a5d58
	blt .counted
	clr.w $a5d58
	move.b $a5d5b,d1
	moveq #1,d0
	abcd d0,d1
	move.b d1,$a5d5b
	cmpi.b #$60,d1
	blt .counted
	clr.b $a5d5b
	move.b $a5d5a,d1
	abcd d0,d1
	move.b d1,$a5d5a
	cmpi.b #$60,d1
	blt .counted
	clr.b $a5d5a
.counted:
	dbf d3,.next
.done:
	rts

; The outer render loop used to notice track-section crossings. Catch-up must
; process each crossing even when no frame is drawn between simulation steps.
step_track_events:
	move.w $a5d38,d1
	move.w $a5d1e,d0
	cmp.w d1,d0
	ble .done
	andi.w #$ff,d1
	lsr.w #6,d1
	andi.w #$ff,d0
	lsr.w #6,d0
	cmp.w d1,d0
	beq .done
	jsr $9080c
.done:
	rts

	IFD STEP_EXTRAPOLATE
	IFNE STEP_FIELDS-2
	IFNE STEP_FIELDS-4
	FAIL "STEP_EXTRAPOLATE requires STEP_FIELDS=2 or 4"
	ENDC
	ENDC
; Presentation experiment: predict forward from the latest simulation state.
; There is no deliberate one-step presentation delay.
; Authoritative actors and camera are restored before publishing completion.
step_save_previous:
	lea $a5d60,a0
	lea step_previous(pc),a1
	move.w #$1180/4-1,d0
.copy:
	move.l (a0)+,(a1)+
	dbf d0,.copy
	rts
step_view_begin:
	lea $a5d60,a0
	lea step_authoritative(pc),a1
	move.w #$1180/4-1,d0
.save:
	move.l (a0)+,(a1)+
	dbf d0,.save
	lea $a5d00,a0
	lea step_camera(pc),a1
	moveq #$4c/4-1,d0
.camera:
	move.l (a0)+,(a1)+
	dbf d0,.camera
	move.l $a5d4c,d7
	sub.l step_stats+8(pc),d7
	cmpi.l #STEP_FIELDS-1,d7
	bls .phase
	moveq #STEP_FIELDS-1,d7
.phase:
	lea step_view_stats(pc),a0
	addq.l #1,8(a0)
	move.l d7,12(a0)
	move.w d7,d0
	lsl.w #2,d0
	addq.l #1,16(a0,d0.w)
	lea step_previous(pc),a1
	lea $a5d60,a2
	moveq #35-1,d6
.actor:
	move.b $6e(a1),d0
	cmp.b $6e(a2),d0
	bne .nextactor
	tst.w $12(a2)
	beq .nextactor
	move.l (a1),d0
	move.l (a2),d1
	bsr .long
	move.l d0,(a2)
	move.l 4(a1),d0
	move.l 4(a2),d1
	bsr .long
	move.l d0,4(a2)
	move.w $30(a1),d0
	ext.l d0
	move.w $30(a2),d1
	ext.l d1
	bsr .long
	move.w d0,$30(a2)
	move.w $32(a1),d0
	ext.l d0
	move.w $32(a2),d1
	ext.l d1
	bsr .long
	move.w d0,$32(a2)
.nextactor:
	lea $80(a1),a1
	lea $80(a2),a2
	dbf d6,.actor
	move.w d7,d0
	mulu #12,d0
	lea step_view_stats+32(pc),a0
	adda.w d0,a0
	move.l step_previous+4(pc),(a0)+
	move.l step_authoritative+4(pc),(a0)+
	move.l $a5d64,(a0)+
	jsr $891ae
	jmp $8970e
.long:
	sub.l d0,d1
	add.l d1,d0
	IFNE STEP_FIELDS-4
	asr.l #1,d1
	ELSE
	asr.l #2,d1
	ENDC
	move.w d7,d2
	beq .done
	subq.w #1,d2
.add:
	add.l d1,d0
	dbf d2,.add
.done:
	rts
step_view_end:
	movem.l d0-d7/a0-a6,-(a7)
	lea step_authoritative(pc),a0
	lea $a5d60,a1
	move.w #$1180/4-1,d0
.restore:
	move.l (a0)+,(a1)+
	dbf d0,.restore
	lea step_camera(pc),a0
	lea $a5d00,a1
	moveq #$4c/4-1,d0
.camera:
	move.l (a0)+,(a1)+
	dbf d0,.camera
	movem.l (a7)+,d0-d7/a0-a6
	jmp $871dc
	cnop 0,4
step_view_stats:
	dc.b 'RRCVIEW1'
	dc.l 0,0
	ds.l 4
	ds.l 12
	ENDC

; Rider spark lifetime is simulation-owned; drawing consults a cached effect.
step_spark_events:
	lea $a5d60,a1
	lea step_sparks(pc),a0
	moveq #35-1,d0
.next:
	clr.b (a0)
	btst #7,$6a(a1)
	beq .advance
	tst.b $6e(a1)
	bne .advance
	tst.b $6f(a1)
	bne .advance
	st.b (a0)
	bclr #7,$6a(a1)
.advance:
	addq.l #1,a0
	lea $80(a1),a1
	dbf d0,.next
	rts
step_spark_test:
	movem.l d0/a0,-(a7)
	move.l a1,d0
	sub.l #$a5d60,d0
	lsr.w #7,d0
	lea step_sparks(pc),a0
	btst #0,(a0,d0.w)
	movem.l (a7)+,d0/a0
	rts
step_sparks:
	ds.b 35
	even

; Pose selection contains attack-state transitions and the sound-event gate at
; $a5991. Run it at the simulation boundary, including invisible catch-up steps.
step_pose_events:
	move.l step_stats+8(pc),d0
	lsr.l #2,d0
	move.b d0,$a598d
	move.b d0,$a5990
	clr.w $a8734
	lea step_pose_busy(pc),a0
	st.b (a0)
	jsr $89d20
	lea step_pose_busy(pc),a0
	clr.b (a0)
	rts
step_pose_clear:
	btst #0,step_pose_busy(pc)
	beq .done
	bclr #4,$68(a1)
.done:
	rts
step_pose_busy:
	dc.b 0
	even

	IFD STEP_EXTRAPOLATE
; Keep large presentation snapshots after code so short PC-relative calls fit.
step_camera:
	ds.b $4c
step_previous:
	ds.b $1180
step_authoritative:
	ds.b $1180
	ENDC

	IFD VERIFY_C_LATENCY
	IFD STEP_EXTRAPOLATE
	FAIL "Latency probe currently requires latest-state presentation"
	ENDC
	include verify_c_latency.s
	ENDC

	IFD VERIFY_C_FAST_STACK
	include verify_c_stack.s
	ENDC
