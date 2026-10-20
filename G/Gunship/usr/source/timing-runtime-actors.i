; Capture after all normal world effects and before scheduler acknowledgement.
; Retained command completion uses the same callback. Script-modal completion
; stays suspended; normal activation seeds a fresh lifecycle prediction.
; a0=arena. Return 0/-3, preserve non-result registers.
timing_runtime_actors:
 cmpi.l #1,RT_READY(a0)
 bne .bad
 tst.w RT_BOUNDARY_PHASE(a0)
 bne .retained
 cmpi.w #1,RT_CAPTURE_OWNER(a0)
 bne .bad
 bra .owner
.retained:
 cmpi.w #4,RT_BOUNDARY_PHASE(a0)
 bne .bad
 tst.w RT_CAPTURE_OWNER(a0)
 bne .bad
.owner:
 cmpi.w #3,RT_CONSUMER+TF_PHASE(a0)
 bne .bad
 cmpi.w #2,RT_BODY+WB_PHASE(a0)
 bne .bad
 cmpi.w #2,RT_SCHEDULER+TS_STATE(a0)
 bne .bad
 cmpi.w #1,RT_SCHEDULER+TS_DUE(a0)
 bne .bad
 move.l d1,-(sp)
 move.l RT_SCHEDULER+TS_FIELD(a0),d1
 cmp.l RT_RECORD+TR_FIELD(a0),d1
 bne .bad_saved
 cmp.l RT_CONSUMER+TF_FIELD(a0),d1
 bne .bad_saved
 tst.w RT_ACTOR_PRESENT+AC_VALID(a0)
 beq .fresh
 move.l RT_CLOCK+TC_TICKS(a0),d1
 cmp.l RT_ACTOR_PRESENT+AC_TICK(a0),d1
 beq .bad_saved
.fresh:
 move.l (sp)+,d1
 bra timing_runtime_actors_seed
.bad_saved:
 move.l (sp)+,d1
.bad:
 moveq #-3,d0
 rts

; Internal: normal activation or the checked post-world callback only.
; Stable prepared bindings, phase0..2; no gameplay callbacks or publication.
timing_runtime_actors_seed:
 movem.l d1/a0-a3,-(sp)
 move.l RT_CLOCK+TC_TICKS(a0),d0
 moveq #0,d1
 move.w RT_CLOCK+TC_PHASE(a0),d1
 lea RT_ACTOR_PREVIEW(a0),a1
 lea RT_ACTOR_GENERATIONS(a0),a2
 movea.l RT_HUNKS+24(a0),a3
 adda.w #$3b88,a3
 lea RT_ACTOR_PRESENT(a0),a0
 bsr actor_present_capture
 movem.l (sp)+,d1/a0-a3
 rts
