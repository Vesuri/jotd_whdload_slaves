; Diagnostic trace of discrete requests issued by the simulation sound gate.
; This measures dispatches, not the timer-driven audio sequencer or audibility.
STEP_EVENT_SLOTS = 1024
step_events_reset:
	lea step_event_stats(pc),a0
	clr.l 8(a0)
	clr.l 12(a0)
	rts
step_event_engine:
	move.w sr,-(a7)
	movem.l d0-d2/a0,-(a7)
	moveq #1,d1
	bsr step_event_log
	movem.l (a7)+,d0-d2/a0
	move.w (a7)+,ccr
	jmp $b506c
step_event_stop:
	move.w sr,-(a7)
	movem.l d0-d2/a0,-(a7)
	moveq #2,d1
	moveq #0,d0 ; this stop request has no sound-number parameter
	bsr step_event_log
	movem.l (a7)+,d0-d2/a0
	move.w (a7)+,ccr
	jmp $b5184
step_event_primary:
	move.w sr,-(a7)
	movem.l d0-d2/a0,-(a7)
	moveq #3,d1
	bsr step_event_log
	movem.l (a7)+,d0-d2/a0
	move.w (a7)+,ccr
	jmp $b507e
step_event_secondary:
	move.w sr,-(a7)
	movem.l d0-d2/a0,-(a7)
	moveq #4,d1
	bsr step_event_log
	movem.l (a7)+,d0-d2/a0
	move.w (a7)+,ccr
	jmp $b507e
step_event_siren:
	move.w sr,-(a7)
	movem.l d0-d2/a0,-(a7)
	moveq #5,d1
	bsr step_event_log
	movem.l (a7)+,d0-d2/a0
	move.w (a7)+,ccr
	jmp $b5052
step_event_log:
	lea step_event_stats(pc),a0
	move.l 8(a0),d2
	cmpi.l #STEP_EVENT_SLOTS,d2
	bcc .overflow
	addq.l #1,8(a0)
	lsl.w #3,d2
	lea 24(a0,d2.w),a0
	move.l step_stats+8(pc),(a0)+
	move.w d1,(a0)+
	move.w d0,(a0)
	rts
.overflow:
	addq.l #1,12(a0)
	rts
	cnop 0,4
step_event_stats:
	dc.b "RRCSEV01"
	dc.l 0,0,STEP_EVENT_SLOTS,8 ; count, overflow, capacity, record bytes
; Each record: historical simulation field (long), kind and parameter (words).
	ds.b STEP_EVENT_SLOTS*8
