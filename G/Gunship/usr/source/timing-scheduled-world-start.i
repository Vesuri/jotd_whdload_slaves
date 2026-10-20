; Once-per-delivered-world-deadline opening. Standalone, not installed.
; Requires scheduler and world-start. Run before deadline commands/motion.
SW_SCHEDULER equ 0
SW_PLAYER equ 4
SW_OPENING equ 8
SW_FIELD equ 12
SW_VALID equ 16
SW_COMMITTED equ 18
SW_SIZE equ 20

; a0=context: three pointers, then metadata zeroed at lifecycle epoch start.
; Return 0 applied, -1 upstream/binding failure, -3 wrong/duplicate phase.
; Preserve other registers. No scheduler acknowledgement or clock rollback.
; COMMITTED means THIS call applied opening, even if the post-check faults.
; FIELD/VALID persist on fault and prevent a retry from advancing game time
; again. Recovery must retain applied-work accounting before explicit rebase.
scheduled_world_start:
	movem.l d1-d2/a0-a2,-(sp)
	movea.l a0,a2
	clr.w SW_COMMITTED(a2)
	movea.l SW_SCHEDULER(a2),a0
	cmpi.w #1,TS_STATE(a0)
	bne .phase
	cmpi.w #1,TS_DUE(a0)
	bne .phase
	bsr scheduler_check
	tst.l d0
	bmi .done
	move.l TS_FIELD(a0),d2
	tst.w SW_VALID(a2)
	beq .apply
	cmp.l SW_FIELD(a2),d2
	beq .phase
.apply:
	movea.l SW_PLAYER(a2),a0
	movea.l SW_OPENING(a2),a1
	bsr world_start_step
	tst.l d0
	bne .done
	move.l d2,SW_FIELD(a2)
	move.w #1,SW_VALID(a2)
	move.w #1,SW_COMMITTED(a2)
	movea.l SW_SCHEDULER(a2),a0
	bsr scheduler_check
	bra .done
.phase:
	moveq #-3,d0
.done:
	movem.l (sp)+,d1-d2/a0-a2
	rts
