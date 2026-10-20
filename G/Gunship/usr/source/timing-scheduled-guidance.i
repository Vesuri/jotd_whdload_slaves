; Once-per-delivered-field guidance bridge. Not installed.
; Requires scheduler and field-guidance. Run before this field's controls/motion.
SG_SCHEDULER equ 0
SG_GUIDANCE equ 4
SG_FIELD equ 8
SG_VALID equ 12
SG_COMMITTED equ 14
SG_SIZE equ 16

; a0=context: two pointers followed by zeroed metadata at epoch start.
; Return 0 inactive, 1 evaluated, -1 upstream fault, -3 wrong/duplicate phase.
; Preserve other registers. Does not acknowledge player motion or world work.
; COMMITTED=1 means evaluation occurred (including inactive), even if a later
; producer fault is reported. Explicit lifecycle rebase must clear metadata.
scheduled_guidance_step:
	movem.l d1-d2/a0-a2,-(sp)
	movea.l a0,a2
	clr.w SG_COMMITTED(a2)
	movea.l SG_SCHEDULER(a2),a0
	cmpi.w #1,TS_STATE(a0)
	bne .phase
	bsr scheduler_check
	tst.l d0
	bmi .done
	move.l TS_FIELD(a0),d2
	tst.w SG_VALID(a2)
	beq .apply
	cmp.l SG_FIELD(a2),d2
	beq .phase
.apply:
	movea.l SG_GUIDANCE(a2),a0
	bsr field_guidance_advance
	move.l d0,d1
	move.l d2,SG_FIELD(a2)
	move.w #1,SG_VALID(a2)
	move.w #1,SG_COMMITTED(a2)
	movea.l SG_SCHEDULER(a2),a0
	bsr scheduler_check
	tst.l d0
	bmi .done
	move.l d1,d0
	bra .done
.phase:
	moveq #-3,d0
.done:
	movem.l (sp)+,d1-d2/a0-a2
	rts
