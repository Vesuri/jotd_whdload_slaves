; Foreground coordinator. No native game hooks yet.
; One field is delivered at a time. The caller must finish its player step,
; then any due world tick, before another field can be delivered.
; a0=state throughout; preserve d1-d7/a0-a6, return status in d0/CCR.
TS_CLOCK      = 0
TS_HISTORY    = 4
TS_COMMANDS   = 8
TS_STATE      = 12             ; 0 ready, 1 player pending, 2 world pending
TS_DUE        = 14
TS_FIELDS     = 16             ; fields left in this snapshot
TS_TICKS      = 18             ; allowed world completions left in this batch
TS_EXCESS     = 20             ; snapshot exceeded the field budget
TS_FAULT      = 22
TS_FIELD      = 24             ; delivered field stamp
TS_COMMAND    = 28             ; delivered command cutoff
TS_STEPS      = 32             ; completed player steps, lifetime
TS_WORLDS     = 36             ; completed world ticks, lifetime
TS_HELD       = 40             ; latest field's held buttons
TS_EDGES      = 44             ; rising edges accumulated for the world interval
TS_SIZE       = 48

; a1=clock, a2=field history, a3=command queue. These must share an epoch
; established by their lifecycle owner with the producer excluded.
scheduler_init:
	move.l a1,TS_CLOCK(a0)
	move.l a2,TS_HISTORY(a0)
	move.l a3,TS_COMMANDS(a0)
	clr.l TS_STATE(a0)
	clr.l TS_FIELDS(a0)
	clr.l TS_EXCESS(a0)
	clr.l TS_FIELD(a0)
	clr.l TS_COMMAND(a0)
	clr.l TS_STEPS(a0)
	clr.l TS_WORLDS(a0)
	clr.l TS_HELD(a0)
	clr.l TS_EDGES(a0)
	moveq #0,d0
	rts

; d0=field budget 1..128, d1=world budget 1..8.
; Snapshot the current backlog so incoming VBLs cannot extend this batch.
; Return 0 success, -1 upstream fault/inactive, -3 invalid phase/arguments.
scheduler_begin:
	tst.w TS_STATE(a0)
	bne scheduler_bad_phase
	tst.w TS_FIELDS(a0)
	bne scheduler_bad_phase
	tst.w TS_EXCESS(a0)
	bne scheduler_bad_phase
	tst.l d0
	beq scheduler_bad_phase
	cmpi.l #128,d0
	bhi scheduler_bad_phase
	tst.l d1
	beq scheduler_bad_phase
	cmpi.l #8,d1
	bhi scheduler_bad_phase
	movem.l d2/a1,-(sp)
	move.l d0,d2
	bsr scheduler_check
	tst.l d0
	bmi .return
	move.w d1,TS_TICKS(a0)
	clr.w TS_EXCESS(a0)
	movea.l TS_HISTORY(a0),a1
	move.w TH_WRITE(a1),d0
	sub.w TH_READ(a1),d0
	cmp.w d2,d0
	bls .fit
	move.w d2,d0
	move.w #1,TS_EXCESS(a0)
.fit:
	move.w d0,TS_FIELDS(a0)
	moveq #0,d0
.return:
	movem.l (sp)+,d2/a1
	rts

; a1=private 32-byte field output. Return 1 field delivered, 0 batch drained,
; -2 budget reached (caller must handle excess explicitly), -1 fault/inactive,
; -3 previous field/world not acknowledged. Never skip a deadline.
scheduler_next:
	tst.w TS_STATE(a0)
	bne scheduler_bad_phase
	movem.l d1-d2/a0-a2,-(sp)
	movea.l a0,a2
	bsr scheduler_check
	tst.l d0
	bmi .return
	tst.w TS_FIELDS(a2)
	beq .finished
	movea.l TS_CLOCK(a2),a0
	move.w TC_PHASE(a0),d0
	addq.w #3,d0
	cmp.w TC_RATE(a0),d0
	blo .take
	tst.w TS_TICKS(a2)
	beq .bound
.take:
	movea.l TS_HISTORY(a2),a0
	bsr history_pop
	cmpi.l #1,d0
	bne .fault                ; a snapshotted record must still be available
	move.l TR_FIELD(a1),d0
	move.l d0,TS_FIELD(a2)
	move.l TR_COMMAND(a1),TS_COMMAND(a2)
	movea.l TS_CLOCK(a2),a0
	bsr clock_field
	tst.l d0
	bmi .fault
	move.w d0,TS_DUE(a2)
	move.l TR_BUTTONS(a1),TS_HELD(a2)
	move.w TR_EDGES(a1),d1
	or.w d1,TS_EDGES(a2)
	subq.w #1,TS_FIELDS(a2)
	move.w #1,TS_STATE(a2)
	movea.l a2,a0
	bsr scheduler_check       ; publication may have faulted during the copy
	tst.l d0
	bmi .return
	moveq #1,d0
	bra .return
.finished:
	tst.w TS_EXCESS(a2)
	bne .bound
	moveq #0,d0
	bra .return
.bound:
	moveq #-2,d0
	bra .return
.fault:
	move.w #1,TS_FAULT(a2)
	moveq #-1,d0
.return:
	movem.l (sp)+,d1-d2/a0-a2
	rts

; Called after applying exactly this field's controls/player step.
; Return 1 if the caller must now run the world, 0 if another field is allowed.
scheduler_player_done:
	cmpi.w #1,TS_STATE(a0)
	bne scheduler_bad_phase
	; The caller has already applied this step. Count it even if a producer
	; fault arrived during the work; recovery cannot undo committed motion.
	addq.l #1,TS_STEPS(a0)
	move.w #2,TS_STATE(a0)
	tst.w TS_DUE(a0)
	bne .check
	clr.w TS_STATE(a0)
.check:
	bsr scheduler_check
	tst.l d0
	bmi .return
	tst.w TS_DUE(a0)
	beq .ready
	move.w #2,TS_STATE(a0)
	moveq #1,d0
	rts
.ready:
	clr.w TS_STATE(a0)
	moveq #0,d0
.return:
	rts

; Called after the due native world tick and world-owned command interval.
scheduler_world_done:
	cmpi.w #2,TS_STATE(a0)
	bne scheduler_bad_phase
	subq.w #1,TS_TICKS(a0)
	addq.l #1,TS_WORLDS(a0)
	clr.w TS_STATE(a0)
	clr.w TS_DUE(a0)
	clr.w TS_EDGES(a0)
	bsr scheduler_check
.return:
	rts

; Explicit recovery only, after the owner has rebased all three upstream
; states and accounted for discarded debt with producers excluded.
; Preserve completed-step counters; abandon only pending/budget state.
scheduler_rebase:
	clr.l TS_STATE(a0)
	clr.l TS_FIELDS(a0)
	clr.l TS_EXCESS(a0)
	clr.l TS_HELD(a0)
	clr.l TS_EDGES(a0)
	move.l a1,-(sp)
	movea.l TS_CLOCK(a0),a1
	move.l TC_LAST(a1),TS_FIELD(a0)
	movea.l TS_COMMANDS(a0),a1
	move.l CQ_LAST(a1),TS_COMMAND(a0)
	move.l (sp)+,a1
	bra scheduler_check

scheduler_bad_phase:
	moveq #-3,d0
	rts

; All three upstream owners must be active and unfaulted. Latch failure:
; neither producer recovery nor a new batch silently resumes this coordinator.
scheduler_check:
	tst.w TS_FAULT(a0)
	bne .bad
	move.l a1,-(sp)
	movea.l TS_CLOCK(a0),a1
	tst.w TC_ACTIVE(a1)
	beq .fault
	tst.w TC_FAULT(a1)
	bne .fault
	movea.l TS_HISTORY(a0),a1
	tst.w TH_ACTIVE(a1)
	beq .fault
	tst.w TH_FAULT(a1)
	bne .fault
	movea.l TS_COMMANDS(a0),a1
	tst.w CQ_ACTIVE(a1)
	beq .fault
	tst.w CQ_FAULT(a1)
	bne .fault
	move.l (sp)+,a1
	moveq #0,d0
	rts
.fault:
	move.l (sp)+,a1
	move.w #1,TS_FAULT(a0)
.bad:
	moveq #-1,d0
	rts
