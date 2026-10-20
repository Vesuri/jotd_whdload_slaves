; Once-per-world-deadline committed geometry. Standalone, not installed.
; Requires scheduler and world-scene. Phase 2 follows committed field motion.
SGE_SCHEDULER equ 0
SGE_PLAYER equ 4
SGE_SCENE equ 8
SGE_OBJECTS equ 12
SGE_FIELD equ 16
SGE_VALID equ 20
SGE_COMMITTED equ 22
SGE_RESULT equ 24
SGE_SIZE equ 26

; a0=context; metadata initialized to zero at lifecycle epoch start.
; Return 0 clear, 1 flight end, -1 failure, -3 wrong/duplicate phase.
; Preserve other registers. Does not acknowledge world completion or clean up.
; COMMITTED describes this call. FIELD/VALID/RESULT survive a post-check fault;
; caller must account for applied flight-end state before recovery/rebasing.
; A positive result must divert to cleanup before weapons/scripts/world tail.
scheduled_world_scene:
 movem.l d1-d2/a0-a3,-(sp)
 movea.l a0,a3
 clr.w SGE_COMMITTED(a3)
 movea.l SGE_SCHEDULER(a3),a0
 cmpi.w #2,TS_STATE(a0)
 bne .phase
 cmpi.w #1,TS_DUE(a0)
 bne .phase
 bsr scheduler_check
 tst.l d0
 bmi .done
 move.l TS_FIELD(a0),d2
 tst.w SGE_VALID(a3)
 beq .apply
 cmp.l SGE_FIELD(a3),d2
 beq .phase
.apply:
 movea.l SGE_PLAYER(a3),a0
 movea.l SGE_SCENE(a3),a1
 movea.l SGE_OBJECTS(a3),a2
 bsr world_scene_check
 tst.l d0
 bmi .done
 move.w d0,SGE_RESULT(a3)
 move.l d2,SGE_FIELD(a3)
 move.w #1,SGE_VALID(a3)
 move.w #1,SGE_COMMITTED(a3)
 movea.l SGE_SCHEDULER(a3),a0
 bsr scheduler_check
 tst.l d0
 bmi .done
 moveq #0,d0
 move.w SGE_RESULT(a3),d0
 bra .done
.phase:
 moveq #-3,d0
.done:
 movem.l (sp)+,d1-d2/a0-a3
 rts
