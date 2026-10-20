; Retained keyboard commands: one producer, independent player/world cursors.
; Both consumers inspect each command, but apply only their owned effects.
; A slot is reusable only after BOTH cursors pass it. Never overwrite unread
; commands. Lifecycle operations require producer exclusion.
; API preserves d1-d7/a0-a6; d0/CCR are results.
CQ_WRITE      = 0
CQ_PLAYER     = 2
CQ_WORLD      = 4
CQ_ACTIVE     = 6
CQ_FAULT      = 8
CQ_LAST       = 12
CQ_LOST       = 16
CQ_DISCARDED  = 20
CQ_RECORDS    = 24
CQ_CAPACITY   = 128
CQ_SIZE       = CQ_RECORDS+CQ_CAPACITY*8

; a0=state, d0=sequence epoch preceding the first command.
commands_init:
	clr.l CQ_WRITE(a0)
	clr.w CQ_WORLD(a0)
	move.w #1,CQ_ACTIVE(a0)
	clr.l CQ_FAULT(a0)
	move.l d0,CQ_LAST(a0)
	clr.l CQ_LOST(a0)
	clr.l CQ_DISCARDED(a0)
	moveq #0,d0
	rts

; a0=state, d0=next sequence, d1.w=native key/modifier word.
; Return 1 published, 0 inactive, -1 fault/loss. Sequence wraps at 32 bits.
commands_publish:
	tst.w CQ_ACTIVE(a0)
	beq .inactive
	tst.w CQ_FAULT(a0)
	bne .lost
	movem.l d2-d3/a1,-(sp)
	move.l d0,d2
	sub.l CQ_LAST(a0),d2
	cmpi.l #1,d2
	bne .reject
	move.w CQ_WRITE(a0),d2
	sub.w CQ_PLAYER(a0),d2
	cmpi.w #CQ_CAPACITY,d2
	bhs .reject
	move.w CQ_WRITE(a0),d2
	sub.w CQ_WORLD(a0),d2
	cmpi.w #CQ_CAPACITY,d2
	bhs .reject
	moveq #0,d2
	move.w CQ_WRITE(a0),d2
	andi.w #CQ_CAPACITY-1,d2
	lsl.w #3,d2
	lea CQ_RECORDS(a0),a1
	adda.w d2,a1
	move.l d0,(a1)
	move.w d1,4(a1)
	clr.w 6(a1)
	addq.w #1,CQ_WRITE(a0)
	; Publish the field's sequence cutoff only after the complete record.
	move.l d0,CQ_LAST(a0)
	movem.l (sp)+,d2-d3/a1
	moveq #1,d0
	rts
.reject:
	movem.l (sp)+,d2-d3/a1
	move.w #1,CQ_FAULT(a0)
.lost:
	addq.l #1,CQ_LOST(a0)
	moveq #-1,d0
	rts
.inactive:
	moveq #0,d0
	rts

; a0=state, a1=private eight-byte destination, d0=field sequence cutoff,
; d1=0 player or 1 world. Return 1 copied, 0 empty/not yet due/inactive,
; -1 fault, -2 invalid role. Cutoffs must come from consecutive field records;
; sequence comparisons assume their distance is less than 2^31 commands.
commands_pop:
	cmpi.l #1,d1
	bhi .role
	tst.w CQ_ACTIVE(a0)
	beq .empty
	tst.w CQ_FAULT(a0)
	bne .bad
	movem.l d2-d3/a2-a3,-(sp)
	lea CQ_PLAYER(a0),a3
	tst.l d1
	beq .cursor
	addq.l #2,a3
.cursor:
	move.w (a3),d2
	cmp.w CQ_WRITE(a0),d2
	beq .none
	andi.w #CQ_CAPACITY-1,d2
	lsl.w #3,d2
	lea CQ_RECORDS(a0),a2
	adda.w d2,a2
	move.l (a2),d3
	sub.l d0,d3
	bgt .none
	move.l (a2),(a1)
	move.l 4(a2),4(a1)
	tst.w CQ_FAULT(a0)
	bne .fault
	addq.w #1,(a3)
	movem.l (sp)+,d2-d3/a2-a3
	moveq #1,d0
	rts
.none:
	movem.l (sp)+,d2-d3/a2-a3
.empty:
	moveq #0,d0
	rts
.fault:
	movem.l (sp)+,d2-d3/a2-a3
.bad:
	moveq #-1,d0
	rts
.role:
	moveq #-2,d0
	rts

commands_pause:
	clr.w CQ_ACTIVE(a0)
	moveq #0,d0
	rts

; a0=state, d0=new sequence epoch. Exclude producer and both consumers.
; Return retained slots discarded (maximum of the two unread counts).
commands_rebase:
	move.l d0,CQ_LAST(a0)
	move.l d1,-(sp)
	moveq #0,d0
	move.w CQ_WRITE(a0),d0
	sub.w CQ_PLAYER(a0),d0
	move.w CQ_WRITE(a0),d1
	sub.w CQ_WORLD(a0),d1
	cmp.w d1,d0
	bhs .count
	move.w d1,d0
.count:
	add.l d0,CQ_DISCARDED(a0)
	move.w CQ_WRITE(a0),CQ_PLAYER(a0)
	move.w CQ_WRITE(a0),CQ_WORLD(a0)
	clr.w CQ_FAULT(a0)
	move.w #1,CQ_ACTIVE(a0)
	move.l (sp)+,d1
	rts
