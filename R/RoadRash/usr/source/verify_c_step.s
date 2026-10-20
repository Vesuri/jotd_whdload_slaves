; Diagnostic C proof, enabled only by VERIFY + VERIFY_C_STEP.
; First-race, CUSTOM2=0 functional experiments only. Not a runtime option.
; STEP_FIELDS=4 is provisional. No interpolation, overflow recovery or complete
; pause/transition/action audit yet. See simulation-timing.md before extending.
; All game addresses below are absolute. Normal builds contain none of this.
;
; RRCSTEP1: cursor +8, count +12, captured field +16, quantum +20,
; frozen $a5900..$a873f at +24. RRCHASH1 follows with 1024 longword actor
; hashes (slot zero unused). Copies/hashes perturb timing: no FPS claims.

	IFND STEP_CAPTURE
STEP_CAPTURE = 601
	ENDC
	IFND STEP_FIELDS
STEP_FIELDS = 4
	ENDC
step_reset:
	movem.l d0-d7/a0-a6,-(a7)
	lea step_stats(pc),a0
	move.l $a5d4c,8(a0)
	clr.l 12(a0)
	clr.l 16(a0)
	lea step_queued_field(pc),a1
	move.l $a5d4c,(a1)
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
	bsr step_actor_animations
	bsr step_derive_lean
	bsr step_scenery_cursor
	jsr $8f552
	lea step_start_frame(pc),a0
	move.w d0,(a0)
	jsr $8eff8
	moveq #0,d0
	lea $a5d60,a0
	move.w #$1180/4-1,d1
.hash:
	rol.l #5,d0
	move.l (a0)+,d2
	eor.l d2,d0
	dbf d1,.hash
	move.l step_stats+12(pc),d1
	cmpi.l #1024,d1
	bcc .nohash
	lsl.w #2,d1
	lea step_hashes+8(pc),a0
	move.l d0,(a0,d1.w)
.nohash:
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
	rts
	cnop 0,4
step_stats:
	dc.b 'RRCSTEP1'
	dc.l 0,0,0,STEP_FIELDS
step_snapshot:
	ds.b $a8740-$a5900

step_hashes:
	dc.b "RRCHASH1"
	ds.l 1024

step_start_sprite:
	move.w step_start_frame(pc),d0
	move.w d0,8(a0)
	rts
step_start_frame:
	dc.w 0

; Field producer: use existing control/pause handling, but keep the physics
; steering and throttle state owned by the simulation consumer.
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
	dbf d4,.next
	lea step_replaying(pc),a0
	clr.b (a0)
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
	bne .done
	move.w #1,$a6ef6
	lea $941d6,a2
	bra .next
.actor:
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
