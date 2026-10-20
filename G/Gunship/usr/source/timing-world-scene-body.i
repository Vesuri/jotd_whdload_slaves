; Geometry-gated post-motion world sequence. Standalone, not installed.
; Requires world-body and scheduled-world-scene. Caller admits a fresh deadline
; by setting WB_PHASE=0, after opening, commands and committed player motion.
; a0=WB context, a1=SGE context. Return as world_body_step: 0 done, 2 modal,
; 3 ended, -1 failure, -3 phase failure. Preserve non-result registers.
; Geometry flight end runs cleanup directly, before weapons/damage/scripts.
; No scheduler acknowledgement. An attempted check consumes WB phase even on
; fault; inspect SGE_COMMITTED/RESULT before lifecycle recovery. Never reset
; phase merely to retry an interrupted/partially applied deadline.
world_scene_body_step:
 movem.l d1-d7/a0-a6,-(sp)
 movea.l a0,a6
 movea.l a1,a4
 tst.w WB_PHASE(a6)
 bne .phase
 bsr world_body_validate
 tst.l d0
 bmi .done
 movea.l WB_PLAYER(a6),a0
 cmpa.l SGE_PLAYER(a4),a0
 bne .bad
 move.w #4,WB_PHASE(a6)
 movea.l a4,a0
 bsr scheduled_world_scene
 tst.l d0
 bmi .done
 bne .collision
 clr.w WB_PHASE(a6)
 movea.l a6,a0
 bsr world_body_step
 bra .done
.collision:
 movea.l WB_PLAYER(a6),a5
 movea.l WB_CLEANUP(a6),a0
 move.l a6,-(sp)
 jsr (a0)
 movea.l (sp)+,a6
 move.w #3,WB_PHASE(a6)
 moveq #3,d0
 bra .done
.phase:
 moveq #-3,d0
 bra .done
.bad:
 moveq #-1,d0
.done:
 movem.l (sp)+,d1-d7/a0-a6
 rts
