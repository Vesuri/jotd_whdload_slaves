; Single interrupt producer / foreground consumer, caller-owned storage.
; Complete records are published with one aligned word store. The consumer
; copies a record before retiring its slot with one aligned word store.
; The adapter must preserve the interrupted CCR/registers around this API.
; init/pause/rebase require producer exclusion (Exec Disable/Enable).
;
; Not yet connected to native input. Record layout and adapter obligations
; are documented in TIMING_DESIGN.md; payload comes from native sampling.

TH_WRITE      = 0               ; monotonic unsigned word cursors
TH_READ       = 2
TH_ACTIVE     = 4
TH_FAULT      = 6
TH_LOST       = 8               ; rejected records since init
TH_DISCARDED  = 12              ; unread records discarded at rebase
TH_LAST       = 16              ; last published field stamp
TH_RECORDS    = 20
TH_CAPACITY   = 128             ; power of two; full capacity is usable
TH_RECORD_SIZE = 32
TH_SIZE       = TH_RECORDS+TH_CAPACITY*TH_RECORD_SIZE

; Record: field.l; native directional x.l/y.l; held buttons.l;
; native relative accumulator x.w/y.w; command sequence.l;
; input mode.w; raw relative delta x.w/y.w; edge mask.w.
TR_FIELD      = 0
TR_X          = 4
TR_Y          = 8
TR_BUTTONS    = 12
TR_RELATIVE   = 16
TR_COMMAND    = 20
TR_MODE       = 24
TR_DX         = 26
TR_DY         = 28
TR_EDGES      = 30

; a0=state, d0=epoch preceding first field. Does not clear unused record bytes.
history_init:
	clr.l TH_WRITE(a0)
	move.w #1,TH_ACTIVE(a0)
	clr.w TH_FAULT(a0)
	clr.l TH_LOST(a0)
	clr.l TH_DISCARDED(a0)
	move.l d0,TH_LAST(a0)
	moveq #0,d0
	rts

; a0=state, a1=complete 32-byte sample. Return 1 published, 0 inactive,
; -1 rejected. Preserve every register except d0/CCR.
; On overflow or a stamp gap, preserve ALL unread data and latch the fault.
; Every subsequent active producer call counts another lost record until rebase.
history_publish:
	tst.w TH_ACTIVE(a0)
	beq .inactive
	tst.w TH_FAULT(a0)
	bne .lost
	movem.l d1-d2/a1-a2,-(sp)
	move.l (a1),d1
	sub.l TH_LAST(a0),d1
	cmpi.l #1,d1
	bne .reject
	move.w TH_WRITE(a0),d1
	sub.w TH_READ(a0),d1
	cmpi.w #TH_CAPACITY,d1
	bhs .reject
	moveq #0,d1
	move.w TH_WRITE(a0),d1
	andi.w #TH_CAPACITY-1,d1
	lsl.w #5,d1
	lea TH_RECORDS(a0),a2
	adda.w d1,a2
	moveq #7,d2
.copy:
	move.l (a1)+,(a2)+
	dbf d2,.copy
	move.l -TH_RECORD_SIZE(a1),TH_LAST(a0)
	addq.w #1,TH_WRITE(a0)       ; publish only after the complete copy
	movem.l (sp)+,d1-d2/a1-a2
	moveq #1,d0
	rts
.reject:
	movem.l (sp)+,d1-d2/a1-a2
	move.w #1,TH_FAULT(a0)
.lost:
	addq.l #1,TH_LOST(a0)
	moveq #-1,d0
	rts
.inactive:
	moveq #0,d0
	rts

; a0=state, a1=private destination (not inside the ring).
; Return 1 copied, 0 empty/inactive, -1 fault. Preserve other registers.
; The foreground coordinator invokes the player once per copied record and
; passes the same interval's controls/events to the world at its deadline.
history_pop:
	tst.w TH_ACTIVE(a0)
	beq .empty
	tst.w TH_FAULT(a0)
	bne .bad
	movem.l d1-d2/a1-a2,-(sp)
	move.w TH_READ(a0),d1
	cmp.w TH_WRITE(a0),d1
	beq .none
	andi.w #TH_CAPACITY-1,d1
	lsl.w #5,d1
	lea TH_RECORDS(a0),a2
	adda.w d1,a2
	moveq #7,d2
.copy:
	move.l (a2)+,(a1)+
	dbf d2,.copy
	; Detect a producer fault during the copy. A later interrupt can still
	; fault before return; the coordinator must also check TH_FAULT.
	tst.w TH_FAULT(a0)
	bne .fault
	addq.w #1,TH_READ(a0)        ; release only after the complete copy
	movem.l (sp)+,d1-d2/a1-a2
	moveq #1,d0
	rts
.none:
	movem.l (sp)+,d1-d2/a1-a2
.empty:
	moveq #0,d0
	rts
.fault:
	movem.l (sp)+,d1-d2/a1-a2
.bad:
	moveq #-1,d0
	rts

; Exclude producer while changing lifecycle state. Disable before dropping.
history_pause:
	clr.w TH_ACTIVE(a0)
	bra history_discard

; a0=state, d0=new epoch. Caller has excluded producer.
history_rebase:
	move.l d0,TH_LAST(a0)
	bsr history_discard
	clr.w TH_FAULT(a0)
	move.w #1,TH_ACTIVE(a0)
	rts

history_discard:
	moveq #0,d0
	move.w TH_WRITE(a0),d0
	sub.w TH_READ(a0),d0
	add.l d0,TH_DISCARDED(a0)
	move.w TH_WRITE(a0),TH_READ(a0)
	rts
