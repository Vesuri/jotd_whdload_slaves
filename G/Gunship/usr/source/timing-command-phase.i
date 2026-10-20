; Bounded command drains for a delivered scheduler field. Not installed.
; Requires scheduler, command-dispatch and world-commands.
; a0=scheduler, a1=CP/CW context, d0=command budget 1..128.
; Return 0 cutoff drained, 2 retained lifecycle boundary, -2 budget exhausted,
; -3 wrong phase/queue/budget, or negative upstream/reader error.
; Preserve all other registers. Never acknowledge player motion or a world tick.
; On -2 the caller must resume this same phase (even if the last command
; exhausted the queue); only a subsequent 0 proves the cutoff is drained.
; Reader COMMITTED/APPLIED remain authoritative after an acknowledgement fault.
command_phase_player:
	movem.l d1-d3/a0-a3,-(sp)
	moveq #1,d2
	lea control_player_next(pc),a3
	bra command_phase_run
command_phase_world:
	movem.l d1-d3/a0-a3,-(sp)
	moveq #2,d2
	lea control_world_next(pc),a3
command_phase_run:
	cmp.w TS_STATE(a0),d2
	bne .bad
	tst.l d0
	beq .bad
	cmpi.l #128,d0
	bhi .bad
	; Both reader contexts start with their queue pointer.
	move.l (a1),d1
	cmp.l TS_COMMANDS(a0),d1
	bne .bad
	move.l d0,d3
	movea.l a0,a2
.loop:
	movea.l a2,a0
	bsr scheduler_check
	tst.l d0
	bmi .done
	move.l TS_COMMAND(a2),d0
	movea.l a1,a0
	jsr (a3)
	move.l d0,d1
	movea.l a2,a0
	bsr scheduler_check
	tst.l d0
	bmi .done
	move.l d1,d0
	cmpi.l #1,d0
	bne .done
	subq.l #1,d3
	bne .loop
	moveq #-2,d0
	bra .done
.bad:
	moveq #-3,d0
.done:
	tst.l d0
	movem.l (sp)+,d1-d3/a0-a3
	rts

; World-primary commands at a due deadline BEFORE its player motion.
; Native +04e3c decoding precedes +0937c; engine/mode state must therefore
; reach the final field's motion before the post-motion world body runs.
; Same arguments/results as command_phase_world. Require player phase with
; TS_DUE=1 and the player reader already drained through this field's cutoff.
; Keep scheduler phase unchanged; command acknowledgement prevents replay
; when the post-player world drain observes the same cutoff again.
command_phase_world_before_player:
	movem.l d1-d3/a0-a3,-(sp)
	cmpi.w #1,TS_STATE(a0)
	bne .bad
	cmpi.w #1,TS_DUE(a0)
	bne .bad
	move.l d0,d3
	movea.l a0,a2
	movea.l a1,a3
	subq.l #8,sp
	movea.l TS_COMMANDS(a0),a0
	movea.l sp,a1
	move.l TS_COMMAND(a2),d0
	moveq #0,d1
	bsr commands_peek
	addq.l #8,sp
	tst.l d0
	bmi .done
	bne .bad
	movea.l a2,a0
	movea.l a3,a1
	move.l d3,d0
	moveq #1,d2
	lea control_world_next(pc),a3
	bra command_phase_run
.bad:
	moveq #-3,d0
.done:
	movem.l (sp)+,d1-d3/a0-a3
	rts
