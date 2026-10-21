; Shared C simulation, selected by CUSTOM2 and the CPU/Fast RAM check below.
; Normal builds use C_RUNTIME_ONLY: no snapshot storage or per-step hashes.
; VERIFY + VERIFY_C_STEP retains the diagnostic capture/replay instrumentation.
; STEP_FIELDS=1 (50 Hz PAL) is the runtime timestep. Larger quanta and whole-view
; extrapolation remain diagnostic experiments, never user-selectable modes.
; Runtime rider-heading prediction affects only presentation.
; Input history exhaustion aborts explicitly. See simulation-timing.md for
; validation results and remaining release checks. Game addresses are absolute.
;
; RRCSTEP1: cursor +8, count +12, captured field +16, quantum +20,
; frozen $a5900..$a873f at +24. RRCHASH2 follows with a longword slot count and actor
; hashes (slot zero unused). STEP_HASH_RING uses RRCHASH3 and publishes a
; completed-step counter for loss-checked host collection across ring wrap.
; Copies/hashes perturb timing: no FPS claims.

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

	IFD VERIFY_C_SEED_ATTACK
	IFND VERIFY_C_EVENTS
	FAIL "Seeded attack requires the event audit"
	ENDC
	ENDC
	IFND STEP_HASH_SLOTS
STEP_HASH_SLOTS = 2048
	ENDC
	IFLT STEP_HASH_SLOTS-2
	FAIL "STEP_HASH_SLOTS needs slot zero and at least one tick"
	ENDC
	IFGT STEP_HASH_SLOTS-8192
	FAIL "STEP_HASH_SLOTS exceeds signed indexed addressing"
	ENDC
	IFD STEP_HASH_RING
	IFD STEP_NO_HASH
	FAIL "STEP_HASH_RING requires hashing"
	ENDC
	IFNE STEP_HASH_SLOTS&(STEP_HASH_SLOTS-1)
	FAIL "STEP_HASH_RING requires a power-of-two capacity"
	ENDC
	ENDC
	IFND STEP_CAPTURE
STEP_CAPTURE = 601
	ENDC
	IFND STEP_FIELDS
STEP_FIELDS = 1
	ENDC
	IFND STEP_INPUT_SLOTS
STEP_INPUT_SLOTS = 2048
	ENDC
	IFLT STEP_INPUT_SLOTS-2
	FAIL "Input history needs at least two slots"
	ENDC
	IFGT STEP_INPUT_SLOTS-32768
	FAIL "Input history exceeds signed word indexing"
	ENDC
	IFNE STEP_INPUT_SLOTS&(STEP_INPUT_SLOTS-1)
	FAIL "Input history capacity must be a power of two"
	ENDC
step_reset:
	movem.l d0-d7/a0-a6,-(a7)
	move.l $a5d4c,d0
	bsr step_reset_history
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

; Native initialization calls the patched race loop and field handler before
; installing the race interrupt. Reset history before those priming calls too.
; Cursor field-1 reproduces the first boot's initial step at field 1.
step_prepare:
	movem.l d0-d7/a0-a6,-(a7)
	move.l $a5d4c,d0
	subq.l #1,d0
	bsr step_reset_history
	lea step_inputs(pc),a0
	move.w #STEP_INPUT_SLOTS-1,d0
.clear:
	clr.b (a0)+
	dbf d0,.clear
	lea step_start_frame(pc),a0
	clr.w (a0)
	movem.l (a7)+,d0-d7/a0-a6
	move.w #1,$a6f00
	rts

; d0 is the initial simulation cursor; the queue follows the live field.
	IFD C_GEOMETRY_REUSE
; Ready byte followed by hardware selection; cleared for every new race.
step_geometry_reuse_flag: dc.w 0
	ENDC
step_reset_history:
	IFD C_GEOMETRY_REUSE
	lea step_geometry_reuse_flag(pc),a1
	clr.w (a1)
	move.l verify_attn(pc),d1
	andi.w #$88,d1 ; AFF_68040 | AFF_68060; 020/030 rebuild normally
	sne 1(a1)
	IFD VERIFY_C_GEOMETRY_REUSE_FORCE
	st 1(a1)
	ENDC
	ENDC
	IFD C_POSE_PREDICT
	IFNE STEP_FIELDS-1
	FAIL "Presentation heading prediction requires one-field simulation"
	ENDC
	IFND POSE_PREDICT_FIELDS
POSE_PREDICT_FIELDS = 3
	ENDC
	lea step_pose_headings(pc),a1
	move.l d0,-(a7)
	moveq #4,d0
.poseclear:
	clr.w (a1)+
	dbf d0,.poseclear
	IFD POSE_PREDICT_MEASURED
	lea step_pose_render_start(pc),a1
	clr.l (a1)+
	clr.w (a1)
	ENDC
	move.l (a7)+,d0
	ENDC
	IFD C_STEERING
	lea step_steering_fraction(pc),a1
	clr.l (a1)
	IFD C_ROAD_TIMING
	lea step_actor_road_fraction(pc),a1
	moveq #34,d1
.actorroadclear:
	clr.l (a1)+
	dbf d1,.actorroadclear
	lea step_road_fraction(pc),a1
	clr.l (a1)+
	clr.l (a1)+
	clr.l (a1)
	ENDC
	ENDC
	lea step_stats(pc),a0
	move.l d0,8(a0)
	clr.l 12(a0)
	clr.l 16(a0)
	IFD STEP_HASH_RING
	lea step_hashes(pc),a1
	clr.l 12(a1)
	ENDC
	lea step_queued_field(pc),a1
	move.l $a5d4c,(a1)
	clr.b step_replaying-step_queued_field(a1)
	clr.b step_input_overflow-step_queued_field(a1)
	IFD VERIFY_C_EVENTS
	bsr step_events_reset
	ENDC
	IFD VERIFY_C_LATENCY
	bsr step_latency_reset
	ENDC
	rts
; Consume every due step without discarding elapsed-time remainder.
step_main:
	btst #0,step_input_overflow(pc)
	bne step_input_failed
; Finish/countdown code can request exit inside a catch-up step. Publish that
; state and let the native outer loop leave the race; never run later ticks.
	tst.w $a59d0
	bne .render
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
	IFD VERIFY_C_SEED_ATTACK
	bsr step_event_seed_attack
	ENDC
	IFD VERIFY_C_SEED_FINISH
	bsr step_seed_finish
	ENDC
	bsr .run
	bra step_main
.run:
	cmpi.w #$20,$a59da
	jmp $87486
.render:
	jmp $875bc
	IFD VERIFY_C_SEED_FINISH
; Synthetic finish-state boundary. Native action code owns the ensuing finish
; countdown and exit request; no direct exit flag or shortened timer is seeded.
step_seed_finish:
	move.l step_stats+8(pc),d0
	cmpi.l #501,d0
	bne .done
	bset #7,$a5dc8
	move.l d0,$a5dc2
	move.w #1,$a5980
	clr.w $a5982
	move.w #18,$a5984
	clr.w $a5986
.done:
	rts
	ENDC
; Run stateful presentation helpers exactly once per simulation step.
step_end:
	IFD C_POSE_PREDICT
	bsr step_predict_history
	ENDC
	jsr $89138
	bsr step_track_events
	bsr step_actor_animations
	bsr step_spark_events
	IFD C_FUSED_LEAN
	nop
	nop
	ELSE
	bsr step_derive_lean
	ENDC
	bsr step_scenery_cursor
	bsr step_pose_events
	jsr $8f552
	lea step_start_frame(pc),a0
	move.w d0,(a0)
	jsr $8eff8
	IFD C_STEERING
	bsr step_steering_finish
	ENDC
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
	IFD STEP_HASH_RING
	andi.w #STEP_HASH_SLOTS-1,d1
	lsl.w #2,d1
	lea step_hashes+16(pc),a0
	move.l d0,(a0,d1.w)
	move.l step_stats+12(pc),-4(a0) ; publish only after the hash is complete
	ELSE
	cmpi.l #STEP_HASH_SLOTS,d1
	bcc .nohash
	lsl.w #2,d1
	lea step_hashes+12(pc),a0
	move.l d0,(a0,d1.w)
	ENDC
.nohash:
	ENDC
	IFND C_RUNTIME_ONLY
	lea step_stats(pc),a0
	IFD STEP_CAPTURE_END
	tst.w $a59d0
	beq .done
	ELSE
	cmpi.l #STEP_CAPTURE,8(a0)
	bne .done
	ENDC
	lea step_snapshot(pc),a1
	lea $a5900,a0
	move.w #($a8740-$a5900)/4-1,d0
.copy:
	move.l (a0)+,(a1)+
	dbf d0,.copy
	lea step_stats(pc),a0
	IFD STEP_CAPTURE_END
	move.l 8(a0),16(a0)
	ELSE
	move.l #STEP_CAPTURE,16(a0)
	ENDC
	ENDC
.done:
	IFD VERIFY_C_LATENCY
	bsr step_latency_simulated
	ENDC
	rts
	cnop 0,4
step_stats:
	dc.b 'RRCSTEP1'
	dc.l 0,0,0,STEP_FIELDS
	IFND C_RUNTIME_ONLY
step_snapshot:
	ds.b $a8740-$a5900

step_hashes:
	IFD STEP_HASH_RING
	dc.b "RRCHASH3"
	dc.l STEP_HASH_SLOTS,0 ; capacity and last completely published step
	ELSE
	dc.b "RRCHASH2"
	dc.l STEP_HASH_SLOTS
	ENDC
	ds.l STEP_HASH_SLOTS

	ENDC

; Keep diagnostic patch targets within the WHDLoad signed-word reach and
; the helper returns within PC-relative reach of the Fast RAM physics copy.
	IFD VERIFY
	IFD REFERENCE_MOTION
	include reference_motion.s
	ENDC
	ENDC
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
	btst #0,step_input_overflow(pc)
	bne .done
	move.l $a5d4c,d3
	cmp.l step_queued_field(pc),d3
	beq .done
	move.l d3,d4
	sub.l step_stats+8(pc),d4
	cmpi.l #STEP_INPUT_SLOTS,d4
	bcc .overflow
	andi.w #STEP_INPUT_SLOTS-1,d3
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
; Check again here: the field interrupt can latch failure after step_main's
; check. An overrun never overwrites buffered history, so an interrupt during
; this replay cannot corrupt a sample already being consumed.
	btst #0,step_input_overflow(pc)
	bne step_input_failed
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
	andi.w #STEP_INPUT_SLOTS-1,d0
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

; Abort from the main task, never from the input interrupt. Continuing after
; missing input would silently change gameplay; do not reset the simulation
; clock or replay stale ring contents to conceal the missing history.
step_input_failed:
	pea step_input_error(pc)
	pea TDREASON_FAILMSG
	move.l _resload(pc),a0
	jmp resload_Abort(a0)
step_input_error:
	dc.b "Enhanced framerate: input history exhausted.",10
	dc.b "The simulation could not keep up. Restart with",10
	dc.b "Enhanced framerate disabled.",0
	even

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
	ds.b STEP_INPUT_SLOTS

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
	bsr step_compute_lean
	bra .next
.done:
	lea step_lean_busy(pc),a0
	clr.b (a0)
	move.w (a7)+,$a6ef6
	rts
; The simulation owns actor +$34. Pose selection reads that stored lean, so
; neither the per-tick pose pass nor a render needs to derive it again.
; Enter past the presentation hook only for the authoritative lean pass.
	IFD C_FUSED_LEAN
	IFND C_RUNTIME_ONLY
; Full snapshot diagnostics need the helper within signed patch reach.
	include lean_pose.s
	ENDC
	ENDC
step_compute_lean:
	sub.l $a5d1e,d2
	jmp $89e76
step_pose_lean:
	jmp $89ef0
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
	IFD VERIFY_C_ROAD_FAST
	IFND VERIFY
	FAIL "Fast road projection experiment requires VERIFY"
	ENDC
	IFD VERIFY_C_GEOMETRY_LUT
	FAIL "Road copy does not yet mirror the later-installed width LUT patch"
	ENDC
; $8970e..$898e1 is a self-contained routine with internal relative branches
; and absolute data references. Keep the mutable word at $898e2 outside it.
step_road_fast_init:
	lea step_road_fast_code(pc),a0
	move.l #$41f9000a,(a0)+
	move.w #$6f3c,(a0)+
	lea $89714,a1
	move.w #($898e2-$89714)/2-1,d0
.copy:
	move.w (a1)+,(a0)+
	dbf d0,.copy
	move.l _resload(pc),a2
	jsr (resload_FlushCache,a2)
	rts
	cnop 0,4
step_road_fast_code:
	ds.b $898e2-$8970e
	ENDC

	IFD C_OBJECT_FAST
; The selected C slave hunk is already verified to be in Fast RAM. All relative
; branches in $8b02e..$8b37d remain inside this block; data addresses are absolute.
; Copy after applying patches so optional width changes are preserved as well.
; Restore the eight-byte entry instruction overwritten by the entry JMP.
; Called once per main-game load, before any native game code resumes.
step_object_fast_init:
	lea step_object_fast_code(pc),a0
	move.l #$33fcffff,(a0)+
	move.l #$000a59e4,(a0)+
	lea $8b036,a1
	move.w #($8b37e-$8b036)/4-1,d0
.copy:
	move.l (a1)+,(a0)+
	dbf d0,.copy
	move.l _resload(pc),a2
	jsr (resload_FlushCache,a2)
	rts
	cnop 0,4
step_object_fast_code:
	ds.b $8b37e-$8b02e
	ENDC

	IFD C_COLLISION_GEOMETRY
	INCLUDE "collision_geometry.s"
	ENDC

step_collision_objects:
	IFD C_COLLISION_GEOMETRY
	IFD C_GEOMETRY_REUSE
	bsr step_geometry_reuse
	ELSE
	bsr step_collision_geometry_code
	ENDC
	ELSE
	jsr $8970e
	ENDC
	clr.w $a8734
	clr.w $a59fc
	jsr $8b02e
	move.w $a8734,$a59fe
	jsr $8a492
	rts

	IFD VERIFY_C_OBJECT_WIDTH
	IFND VERIFY
	FAIL "Object width experiment requires VERIFY"
	ENDC
; $8b2e8's numerator D3 and divisor D1 survive the native rejection tests.
; Rejected records are not published; accepted records need their width before
; D3 is reused for projected height at $8b332. Restore displaced instructions.
step_object_width:
	divu.w d1,d3
	move.w d3,4(a0)
	add.w d2,d2
	lea $a7068,a2
	rts
	ENDC

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
; Pose selection above $89f48 owns attack transitions and sound gates.
; Everything after it emits projection/effect records. The next simulation
; tick rebuilds collision records independently; only a render needs these.
step_pose_project:
	btst #0,step_pose_busy(pc)
	bne .next
	move.l 4(a1),d0
	sub.l $a5d1e,d0
	jmp $89f52
.next:
	jmp $89d5e
step_pose_busy:
	dc.b 0
	even

	IFD C_POSE_PREDICT
; Estimate presentation heading from the latest authoritative increment.
; Integer heading can repeat during a continuing turn: on those ticks use
; the four-tick average. History stores four times the estimated rate so the
; prediction multiply below retains its existing quarter-unit scaling.
; Runtime uses the measured render interval; diagnostics can fix the horizon.
; Never write prediction to an actor or use it in the simulation pose pass.
step_predict_history:
	movem.l d0-d2/a0,-(a7)
	move.l step_stats+8(pc),d0
	andi.w #3,d0
	add.w d0,d0
	lea step_pose_headings(pc),a0
	move.w $a5d6c,d1
	move.w d1,d2
	subq.w #2,d0
	andi.w #6,d0
	sub.w (a0,d0.w),d2
	addq.w #2,d0
	andi.w #6,d0
	tst.w d2
	beq .average
	lsl.w #2,d2
	bra .store
.average:
	move.w d1,d2
	sub.w (a0,d0.w),d2
.store:
	move.w d1,(a0,d0.w)
	move.w d2,8(a0)
	movem.l (a7)+,d0-d2/a0
	rts
step_predict_pose:
	move.w $c(a1),d1
	cmpa.l #$a5d60,a1
	bne .done
	btst #0,step_pose_busy(pc)
	bne .done
	movem.l d0/d2,-(a7)
	move.w step_pose_headings+8(pc),d2
	move.b $a598c,d0
	andi.b #12,d0
	tst.w d2
	beq .restore
	bmi .left
	cmpi.b #8,d0
	bne .restore
	tst.w d1
	bmi .restore
	bra .predict
.left:
	cmpi.b #4,d0
	bne .restore
; The native mirror bit was already chosen from the authoritative heading.
; At zero it uses the positive orientation; do not predict across that sign.
	tst.w d1
	bge .restore
.predict:
	IFD POSE_PREDICT_MEASURED
	muls.w step_pose_render_fields(pc),d2
	ELSE
	muls.w #POSE_PREDICT_FIELDS,d2
	ENDC
	asr.l #2,d2
	add.w d2,d1
.restore:
	movem.l (a7)+,d0/d2
.done:
	cmpa.l #$a5d60,a1
	rts
step_pose_headings:
	ds.w 5
	IFD POSE_PREDICT_MEASURED
; Observe drawing plus the native vsync handoff. Start conservatively at zero
; after each reset and bound extrapolation to four fields even after a stall.
; These hooks neither delay presentation nor alter its original handshake.
step_predict_render_begin:
	move.l a0,-(a7)
	IFD C_GEOMETRY_REUSE
	lea step_geometry_reuse_flag(pc),a0
	move.b 1(a0),(a0)
	ENDC
	lea step_pose_render_start(pc),a0
	move.l $a5d4c,(a0)
	move.l (a7)+,a0
	jmp $8970e
step_predict_render_end:
	movem.l d0/a0,-(a7)
	move.l $a5d4c,d0
	sub.l step_pose_render_start(pc),d0
	cmpi.l #4,d0
	bls .store
	moveq #4,d0
.store:
	lea step_pose_render_fields(pc),a0
	move.w d0,(a0)
	movem.l (a7)+,d0/a0
	jmp $b2b2c
step_pose_render_start:
	dc.l 0
step_pose_render_fields:
	dc.w 0
	ENDC
	ENDC

	IFD C_STEERING
	include steering.s
	ENDC

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

	IFD C_FAST_STACK
	include runtime_stack.s
	ENDC

	IFD VERIFY_C_EVENTS
	IFD STEP_EXTRAPOLATE
	FAIL "Event audit currently requires latest-state presentation"
	ENDC
	include verify_c_events.s
	ENDC

	IFD C_PHYSICS_FAST
	include physics_fast.s
	ENDC

	IFD C_PHYSICS_AUX
	include physics_aux.s
	ENDC

	IFD C_FUSED_LEAN
	IFD C_RUNTIME_ONLY
; Preserve the measured normal-runtime layout independently of diagnostics.
	include lean_pose.s
	ENDC
	ENDC

	IFD C_GEOMETRY_REUSE
; Consume render geometry once, before the next movement update.
; Additional catch-up ticks rebuild it normally; no tick or input is skipped.
step_geometry_reuse:
 lea step_geometry_reuse(pc),a0
 suba.l #step_geometry_reuse-step_geometry_reuse_flag,a0
 tst.b (a0)
 beq .build
 clr.b (a0)
 rts
.build:
 jmp step_collision_geometry_code(pc)
	ENDC

	IFND VERIFY
	IFD REFERENCE_MOTION
	include reference_motion.s
	ENDC
	ENDC
