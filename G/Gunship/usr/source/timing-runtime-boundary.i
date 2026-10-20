; Retain a keyboard lifecycle boundary before native UI execution.
; Pending field/tick remains owned until completion or explicit native exit.
; a0=arena throughout; non-result registers preserved.

; Caller excludes producer and consumers. Return 0 suspended, -3 invalid.
; All rejection checks precede writes. Unread fields are discarded/accounted;
; command queue and delivered record remain retained for completion.
timing_runtime_boundary_suspend:
 movem.l d1-d7/a0-a6,-(sp)
 subq.l #8,sp
 movea.l a0,a6
 cmpi.l #1,RT_READY(a6)
 bne .bad
 moveq #1,d7
 move.w RT_BOUNDARY_PHASE(a6),d0
 beq .ownership
 cmpi.w #4,d0
 bne .bad
 moveq #0,d7 ; another boundary in the same suspended field
.ownership:
 cmp.w RT_CAPTURE_OWNER(a6),d7
 bne .bad
 tst.l RT_BOUNDARY(a6)
 beq .bad
 cmpi.w #2,RT_BATCH(a6)
 bne .bad
 cmpi.w #1,RT_SCHEDULER+TS_STATE(a6)
 bne .bad
 cmpi.w #1,RT_CONSUMER+TF_PHASE(a6)
 bne .bad
 tst.w RT_PLAYER_READER+CP_COMMITTED(a6)
 bne .bad
 cmp.w RT_CLOCK+TC_ACTIVE(a6),d7
 bne .bad
 cmp.w RT_HISTORY+TH_ACTIVE(a6),d7
 bne .bad
 cmp.w RT_COMMANDS+CQ_ACTIVE(a6),d7
 bne .bad
 move.w RT_CLOCK+TC_FAULT(a6),d0
 or.w RT_HISTORY+TH_FAULT(a6),d0
 or.w RT_COMMANDS+CQ_FAULT(a6),d0
 or.w RT_SCHEDULER+TS_FAULT(a6),d0
 bne .bad
 lea RT_COMMANDS(a6),a0
 move.w CQ_WRITE(a0),d0
 sub.w CQ_PLAYER(a0),d0
 beq .bad
 cmpi.w #CQ_CAPACITY,d0
 bhi .bad
 move.w CQ_PLAYER(a0),d0
 andi.w #CQ_CAPACITY-1,d0
 lsl.w #3,d0
 lea CQ_RECORDS(a0),a1
 adda.w d0,a1
 move.l (a1),(sp)
 move.l 4(a1),4(sp)
 move.l (sp),d0
 sub.l RT_SCHEDULER+TS_COMMAND(a6),d0
 bgt .bad
 move.l (sp),d0
 cmp.l RT_PLAYER_READER+CP_SEQUENCE(a6),d0
 bne .bad
 move.w 4(sp),d0
 cmp.w RT_PLAYER_READER+CP_KEY(a6),d0
 bne .bad
 tst.w 6(sp)
 bne .bad
 bsr control_command_class
 cmpi.l #CC_BOUNDARY,d0
 bne .bad
 move.l (sp),RT_BOUNDARY_RECORD(a6)
 move.l 4(sp),RT_BOUNDARY_RECORD+4(a6)
 clr.w RT_BOUNDARY_RESULT(a6)
 move.w #1,RT_BOUNDARY_PHASE(a6)
 movea.l a6,a0
 bsr timing_runtime_suspend
 bra .done
.bad:
 moveq #-3,d0
.done:
 addq.l #8,sp
 movem.l (sp)+,d1-d7/a0-a6
 rts

; Complete the one retained field after a marked native command.
; a0=arena, d0=command budget 1..128. Return 0 complete (still paused),
; 1 budget yield, 2 another keyboard boundary, 3 script modal already
; suspended, 4 flight ended, -1 failure, -3 invalid admission.
; Installed producer adapters exclude all retained boundary phases, so
; interrupts may run while the old consumers are temporarily active.
; Those adapters or external producer exclusion are required.
; Never deliver another history record. Caller serializes foreground owners.
timing_runtime_boundary_finish:
 movem.l d1-d7/a0-a6,-(sp)
 movea.l a0,a6
 move.l d0,d7
 tst.l d7
 beq .bad
 cmpi.l #128,d7
 bhi .bad
 cmpi.l #1,RT_READY(a6)
 bne .bad
 tst.w RT_CAPTURE_OWNER(a6)
 bne .bad
 move.w RT_CLOCK+TC_ACTIVE(a6),d0
 or.w RT_HISTORY+TH_ACTIVE(a6),d0
 or.w RT_COMMANDS+CQ_ACTIVE(a6),d0
 bne .bad
 cmpi.w #1,RT_SCHEDULER+TS_STATE(a6)
 bne .bad
 move.w RT_CONSUMER+TF_PHASE(a6),d0
 cmpi.w #1,d0
 beq .phase
 cmpi.w #2,d0
 bne .bad
.phase:
 cmpi.w #5,RT_BOUNDARY_PHASE(a6)
 beq .abort
 cmpi.w #4,RT_BOUNDARY_PHASE(a6)
 bne .bad
 move.w #1,RT_CLOCK+TC_ACTIVE(a6)
 move.w #1,RT_HISTORY+TH_ACTIVE(a6)
 move.w #1,RT_COMMANDS+CQ_ACTIVE(a6)
 lea RT_CONSUMER(a6),a0
 move.l d7,d0
 bsr timing_flight_consume
 move.l d0,d6
 cmpi.l #3,d6
 bne .pause
 ; Script modal admission checks active owners before suspending them.
 movea.l a6,a0
 bsr timing_runtime_modal_suspend
 tst.l d0
 beq .pause
 moveq #-1,d6
.pause:
 clr.w RT_CLOCK+TC_ACTIVE(a6)
 clr.w RT_HISTORY+TH_ACTIVE(a6)
 clr.w RT_COMMANDS+CQ_ACTIVE(a6)
 cmpi.l #-2,d6
 beq .yield
 cmpi.l #2,d6
 beq .boundary
 cmpi.l #3,d6
 beq .modal
 tst.l d6
 bmi .failed
 cmpi.l #4,d6
 beq .ended
 ; No unread snapshot survives suspension. A fresh epoch is explicit.
 clr.w RT_SCHEDULER+TS_FIELDS(a6)
 clr.w RT_SCHEDULER+TS_EXCESS(a6)
 clr.w RT_BATCH(a6)
 moveq #0,d0
 bra .done
.abort:
 ; Native exit skips motion/world tail and returns to outer flight cleanup.
 ; Account the aborted delivered field, not a fictitious completed step/tick.
 addq.l #1,RT_BOUNDARY_ABORTS(a6)
 lea RT_COMMANDS(a6),a0
 move.l RT_CAPTURE+24(a6),d0
 bsr commands_rebase
 clr.w RT_COMMANDS+CQ_ACTIVE(a6)
 clr.w RT_SCHEDULER+TS_STATE(a6)
 clr.w RT_SCHEDULER+TS_DUE(a6)
 move.w #6,RT_CONSUMER+TF_PHASE(a6)
.ended:
 clr.w RT_SCHEDULER+TS_FIELDS(a6)
 clr.w RT_SCHEDULER+TS_EXCESS(a6)
 move.w #4,RT_BATCH(a6)
 moveq #4,d0
 bra .done
.yield:
 moveq #1,d0
 bra .done
.boundary:
 move.w #2,RT_BATCH(a6)
 moveq #2,d0
 bra .done
.modal:
 move.w #3,RT_BATCH(a6)
 moveq #3,d0
 bra .done
.failed:
 move.w #6,RT_BOUNDARY_PHASE(a6)
 move.w #5,RT_BATCH(a6)
 moveq #-1,d0
 bra .done
.bad:
 moveq #-3,d0
.done:
 movem.l (sp)+,d1-d7/a0-a6
 rts

; Run after interrupts have been restored. Native UI owns keyboard input;
; private sampling stays off. Return 0 completed/marked, 4 ended/marked,
; -1 execution/mark failure, -3 invalid admission. Repeated calls reject.
; Phase 3 preserves evidence that effects ran even if marking subsequently
; fails. Neither a new epoch nor another native execution is allowed then.
timing_runtime_boundary_run:
 movem.l d1-d7/a0-a6,-(sp)
 movea.l a0,a6
 cmpi.l #1,RT_READY(a6)
 bne .bad
 cmpi.w #1,RT_BOUNDARY_PHASE(a6)
 bne .bad
 tst.w RT_CAPTURE_OWNER(a6)
 bne .bad
 move.w RT_CLOCK+TC_ACTIVE(a6),d0
 or.w RT_HISTORY+TH_ACTIVE(a6),d0
 or.w RT_COMMANDS+CQ_ACTIVE(a6),d0
 bne .bad
 cmpi.w #1,RT_SCHEDULER+TS_STATE(a6)
 bne .bad
 cmpi.w #1,RT_CONSUMER+TF_PHASE(a6)
 bne .bad
 movea.l RT_HUNKS+24(a6),a2
 movea.l RT_HUNKS+20(a6),a0
 cmpa.l $60(a0),a2
 bne .bad
 move.w #2,RT_BOUNDARY_PHASE(a6)
 lea $3b88(a2),a0
 lea RT_BOUNDARY(a6),a1
 moveq #0,d0
 move.w RT_BOUNDARY_RECORD+4(a6),d0
 bsr boundary_command_step
 tst.l d0
 beq .executed
 cmpi.l #4,d0
 bne .failed
.executed:
 move.w d0,RT_BOUNDARY_RESULT(a6)
 move.w #3,RT_BOUNDARY_PHASE(a6)
 lea RT_COMMANDS(a6),a0
 lea RT_BOUNDARY_RECORD(a6),a1
 bsr boundary_command_mark
 cmpi.l #1,d0
 bne .mark_failed
 move.w #4,RT_BOUNDARY_PHASE(a6)
 moveq #0,d0
 move.w RT_BOUNDARY_RESULT(a6),d0
 beq .done
 move.w #5,RT_BOUNDARY_PHASE(a6)
 bra .done
.failed:
 move.w #6,RT_BOUNDARY_PHASE(a6)
.mark_failed:
 moveq #-1,d0
 bra .done
.bad:
 moveq #-3,d0
.done:
 movem.l (sp)+,d1-d7/a0-a6
 rts
