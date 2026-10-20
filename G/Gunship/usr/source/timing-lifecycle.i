; Core timing lifecycle. Requires clock/history/commands/scheduler/endpoint-player.
; Caller excludes the interrupt producer and both foreground consumers for
; the entire call. Stable, initialized, nonoverlapping bindings are required.
; Not installed. Native modal completion, pending ground-event publication,
; and reset of prediction/once-only helper metadata remain adapter duties.
;
; a0=TS scheduler. Preserve non-result registers. Return 0.
; Retain scheduler phase: suspension must not erase an unfinished world tick.
; Commands stay retained until resume; unread field records are discarded now.
timing_suspend:
	movem.l a0-a1,-(sp)
	movea.l a0,a1
	movea.l TS_CLOCK(a1),a0
	bsr clock_pause
	movea.l TS_COMMANDS(a1),a0
	bsr commands_pause
	movea.l TS_HISTORY(a1),a0
	bsr history_pause
	moveq #0,d0
	movem.l (sp)+,a0-a1
	rts

; a0=TS, a1=EP, d0=new field epoch, d1=new command sequence epoch,
; d2=previous Y (-1..1), sampled by the adapter at the new epoch.
; Return 0 success, -3 invalid arguments/phase without writes.
; Resume only after resolving the suspended delivered field/world and any
; pending side effects. The caller must reset helper replay/presentation
; metadata while sampling is disabled, before this call enables all owners.
; Preserve lifetime clock/scheduler/loss counters; discard only unread debt,
; clock remainder and endpoint fractions/history. Native player is untouched.
timing_resume:
	movem.l d1-d7/a0-a6,-(sp)
	movea.l a0,a4
	movea.l a1,a5
	move.l d0,d4
	move.l d1,d5
	tst.w TS_STATE(a4)
	bne .bad
	movea.l TS_CLOCK(a4),a0
	tst.w TC_ACTIVE(a0)
	bne .bad
	moveq #0,d3
	move.w TC_RATE(a0),d3
	cmpi.w #50,d3
	beq .rate
	cmpi.w #60,d3
	bne .bad
.rate:
	movea.l TS_HISTORY(a4),a0
	tst.w TH_ACTIVE(a0)
	bne .bad
	movea.l TS_COMMANDS(a4),a0
	tst.w CQ_ACTIVE(a0)
	bne .bad
	cmpi.l #-1,d2
	blt .bad
	cmpi.l #1,d2
	bgt .bad
	; All rejecting conditions precede the first write.
	movea.l a5,a0
	move.l d3,d0
	move.l d2,d1
	bsr endpoint_player_init
	movea.l TS_CLOCK(a4),a0
	move.l d4,d0
	bsr clock_rebase
	movea.l TS_HISTORY(a4),a0
	move.l d4,d0
	bsr history_rebase
	movea.l TS_COMMANDS(a4),a0
	move.l d5,d0
	bsr commands_rebase
	movea.l a4,a0
	bsr scheduler_rebase
	bra .done
.bad:
	moveq #-3,d0
.done:
	movem.l (sp)+,d1-d7/a0-a6
	rts
