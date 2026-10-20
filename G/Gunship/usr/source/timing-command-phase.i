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
