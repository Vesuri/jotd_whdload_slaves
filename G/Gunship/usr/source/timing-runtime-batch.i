; Foreground delivery/consumer loop for one bounded backlog snapshot.
; No rendering or lifecycle calls here: caller handles returned boundaries.
; a0=prepared, activated arena; d0=field budget 1..128,
; d1=world budget 1..8, d2=command budget per reader 1..128.
; Return 0 snapshot drained, 1 command-budget yield, 2 retained lifecycle
; command, 3 script modal, 4 flight ended, 5 render yield, -2 excess time, -1 fault,
; -3 invalid admission. Preserve all other registers.
; A retry after 1/2 resumes the delivered field, never a new snapshot.
; Fault/excess/end/modal stay latched until explicit lifecycle resolution.
; Producers may publish while running; only the initial backlog is drained.
timing_runtime_batch:
 movem.l d1-d7/a0-a6,-(sp)
 movea.l a0,a6
 cmpi.l #1,RT_READY(a6)
 bne .bad
 cmpi.w #1,RT_CAPTURE_OWNER(a6)
 bne .bad
 tst.l d0
 beq .bad
 cmpi.l #128,d0
 bhi .bad
 tst.l d1
 beq .bad
 cmpi.l #8,d1
 bhi .bad
 tst.l d2
 beq .bad
 cmpi.l #128,d2
 bhi .bad
 move.l d2,d7
 move.w RT_BATCH(a6),d2
 beq .begin
 cmpi.w #1,d2
 beq .resume
 cmpi.w #2,d2
 beq .resume
 cmpi.w #3,d2
 beq .modal
 cmpi.w #4,d2
 beq .ended
 cmpi.w #5,d2
 beq .fault
 cmpi.w #6,d2
 beq .excess
 bra .bad
.begin:
 tst.w RT_SCHEDULER+TS_STATE(a6)
 bne .bad
 tst.w RT_SCHEDULER+TS_FIELDS(a6)
 bne .bad
 tst.w RT_SCHEDULER+TS_EXCESS(a6)
 bne .bad
 lea RT_SCHEDULER(a6),a0
 bsr scheduler_begin
 tst.l d0
 bne .failed
 move.w #1,RT_BATCH(a6)
 bra .next
.resume:
 ; Only a retained command-reader phase may resume a delivered field.
 cmpi.w #1,RT_SCHEDULER+TS_STATE(a6)
 bne .bad
 move.w RT_CONSUMER+TF_PHASE(a6),d2
 cmpi.w #1,d2
 beq .consume
 cmpi.w #2,d2
 bne .bad
 bra .consume
.next:
 lea RT_SCHEDULER(a6),a0
 lea RT_RECORD(a6),a1
 bsr scheduler_next
 tst.l d0
 beq .drained
 cmpi.l #-2,d0
 beq .budget
 cmpi.l #1,d0
 bne .failed
.consume:
 lea RT_CONSUMER(a6),a0
 move.l d7,d0
 bsr timing_flight_consume
 tst.l d0
 beq .next
 cmpi.l #1,d0
 beq .next
 cmpi.l #-2,d0
 beq .yield
 cmpi.l #2,d0
 beq .boundary
 cmpi.l #3,d0
 beq .modal
 cmpi.l #4,d0
 beq .ended
.failed:
 ; An invalid internal phase is not permission to retry native side effects.
 move.w #5,RT_BATCH(a6)
.fault:
 moveq #-1,d0
 bra .done
.budget:
 ; A world allowance is a fairness bound, not evidence of excess time.
 ; Keep unread records and clock phase; the next batch resnapshots them
 ; after drawing. Only an oversized field snapshot requires a rebase.
 tst.w RT_SCHEDULER+TS_EXCESS(a6)
 bne .excess
 clr.w RT_SCHEDULER+TS_FIELDS(a6)
 clr.w RT_SCHEDULER+TS_TICKS(a6)
 clr.w RT_BATCH(a6)
 moveq #5,d0
 bra .done
.excess:
 move.w #6,RT_BATCH(a6)
 moveq #-2,d0
 bra .done
.yield:
 move.w #1,RT_BATCH(a6)
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
.ended:
 move.w #4,RT_BATCH(a6)
 moveq #4,d0
 bra .done
.drained:
 clr.w RT_BATCH(a6)
 moveq #0,d0
 bra .done
.bad:
 moveq #-3,d0
.done:
 movem.l (sp)+,d1-d7/a0-a6
 rts
