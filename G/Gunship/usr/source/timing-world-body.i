; Once-only post-motion world sequence. Standalone, not installed.
; Requires weapons, damage, script and tail modules. Initialize pointers and
; WB_PHASE=0 for each newly admitted world tick, never to retry a partial tick.
WB_PLAYER equ 0
WB_WEAPONS equ 4
WB_DAMAGE equ 8
WB_SCRIPT equ 12
WB_RESERVES equ 16
WB_PERIODIC equ 20
WB_CLEANUP equ 24
WB_PHASE equ 28              ; 0 ready, 1 modal, 2 done, 3 ended, 4 in-progress/error
WB_SIZE equ 30

; a0=context. Return 0 completed, 2 modal boundary, 3 flight ended,
; -1 binding/child failure, -3 wrong phase. Preserve non-result registers.
; Caller owns stable, prepared, nonoverlapping clones and context.
; Opening, commands and player motion precede this entry.
world_body_step:
	movem.l d1-d7/a0-a6,-(sp)
	movea.l a0,a6
	tst.w WB_PHASE(a6)
	bne .phase
	bsr world_body_validate
	tst.l d0
	bmi .done
	move.w #4,WB_PHASE(a6)
	movea.l WB_PLAYER(a6),a0
	movea.l WB_WEAPONS(a6),a1
	bsr world_weapons_step
	tst.l d0
	bne .failed
	movea.l WB_DAMAGE(a6),a1
	bsr world_damage_step
	tst.l d0
	bne .failed
	movea.l WB_SCRIPT(a6),a1
	bsr world_script_step
	cmpi.l #2,d0
	beq .modal
	tst.l d0
	bne .failed
	bsr world_body_tail
	bra .done
.modal:
	move.w #1,WB_PHASE(a6)
	bra .done
.phase:
	moveq #-3,d0
	bra .done
.failed:
	moveq #-1,d0
.done:
	movem.l (sp)+,d1-d7/a0-a6
	rts

; ONLY after the lifecycle owner has completed native +08050. This entry
; cannot establish that fact itself. It never replays weapons/damage/prefix.
; No scheduler acknowledgement or lifecycle rebase is performed here.
world_body_resume:
	movem.l d1-d7/a0-a6,-(sp)
	movea.l a0,a6
	cmpi.w #1,WB_PHASE(a6)
	bne .phase
	bsr world_body_validate
	tst.l d0
	bmi .done
	move.w #4,WB_PHASE(a6)
	movea.l WB_PLAYER(a6),a0
	movea.l WB_SCRIPT(a6),a1
	bsr world_script_resume
	tst.l d0
	bne .failed
	bsr world_body_tail
	bra .done
.phase:
	moveq #-3,d0
	bra .done
.failed:
	moveq #-1,d0
.done:
	movem.l (sp)+,d1-d7/a0-a6
	rts

; Preflight every binding before any authoritative effects, including tail.
world_body_validate:
	movea.l WB_PLAYER(a6),a0
	movea.l WB_WEAPONS(a6),a1
	cmpa.l WW_CODE_SIZE(a1),a0
	bne .bad
	movea.l WB_DAMAGE(a6),a1
	cmpa.l WD_CODE_SIZE(a1),a0
	bne .bad
	movea.l WB_SCRIPT(a6),a1
	cmpa.l SC_PLAYER(a1),a0
	bne .bad
	movea.l WB_PERIODIC(a6),a1
	cmpa.l WP_CODE_SIZE(a1),a0
	bne .bad
	moveq #0,d0
	rts
.bad:
	moveq #-1,d0
	rts

world_body_tail:
	movea.l WB_PLAYER(a6),a0
	movea.l WB_RESERVES(a6),a1
	movea.l WB_PERIODIC(a6),a2
	movea.l WB_CLEANUP(a6),a3
	bsr world_tail_step
	cmpi.l #2,d0
	beq .ended
	tst.l d0
	bmi .failed
	move.w #2,WB_PHASE(a6)
	moveq #0,d0
	rts
.ended:
	move.w #3,WB_PHASE(a6)
	moveq #3,d0
	rts
.failed:
	moveq #-1,d0
	rts
