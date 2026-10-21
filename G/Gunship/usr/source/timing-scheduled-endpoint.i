; Scheduler bridge for endpoint-player, with optional deferred ground.
; Requires endpoint-ground-resolve; not installed in the native game loop.
; Copies retain the private-then-publish transaction, using word-aligned
; 16-byte groups and exact tails to reduce per-field copying overhead.
; Endpoint calculation borrows this workspace; only this bridge publishes
; after the final producer-health check and deferred-ground resolution.
SE_OWNER equ 0
SE_PLAYER equ 4
SE_STAGES equ 8
SE_SINE equ 12
SE_PACKET equ 16
SE_SCHEDULER equ 20
SE_FIELD equ 24
SE_COMMITTED equ 28
SE_SIZE equ 30
SE_GROUND equ SE_SIZE
SE_EVENT equ SE_SIZE+4
SE_CACHE equ SE_SIZE+8 ; optional player preview cache, initially null
SE_GROUND_SIZE equ SE_SIZE+12
SE_WORK_PLAYER equ EP_WORK_OUTPUT
SE_WORK_COMMAND equ EP_WORK_SIZE
SE_WORK_SIZE equ SE_WORK_COMMAND+8

; a0=context (six pointers, remaining bytes initially zero),
; a1=delivered history record, d0=upcoming logical world tick.
; Return 0 field complete, 1 world due, -1 fault, -3 phase/binding mismatch.
; Other registers preserved. Caller has decoded controls and drained ordinary
; commands; deadline world commands must also be drained before this call.
; Private state/player copies survive no rejection. COMMITTED distinguishes a
; producer fault after publication; scheduler counts that applied field once.
; World effects, ground handling and lifecycle remain caller-owned.
scheduled_endpoint_step:
	move.l d1,-(sp)
	moveq #0,d1
	bsr scheduled_endpoint_common
	move.l (sp)+,d1
	rts

; Extended context binds a deferred ground clone and its stable event.
; Resolve contact privately on due fields. Caller commits the event only
; after COMMITTED=1, including a fault after publication. A pending event
; blocks further steps; rejection discards only events created by this call.
scheduled_endpoint_ground_step:
	move.l d1,-(sp)
	moveq #1,d1
	bsr scheduled_endpoint_common
	move.l (sp)+,d1
	rts

scheduled_endpoint_common:
	movem.l d1-d7/a0-a6,-(sp)
	suba.w #SE_WORK_SIZE+4,sp
	movea.l sp,a5
	move.w d1,SE_WORK_SIZE(a5)
	clr.w SE_WORK_SIZE+2(a5)	; this call prepared an event
	movea.l a0,a6
	clr.w SE_COMMITTED(a6)
	tst.w d1
	beq .binding
	tst.l SE_GROUND(a6)
	beq .phase
	tst.l SE_EVENT(a6)
	beq .phase
	movea.l SE_EVENT(a6),a2
	tst.l (a2)
	bne .phase
.binding:
	move.l d0,d7
	cmpi.l #65535,d7
	bhi .phase
	movea.l SE_SCHEDULER(a6),a0
	move.l a0,d5
	cmpi.w #1,TS_STATE(a0)
	bne .phase
	move.l TR_FIELD(a1),d6
	cmp.l TS_FIELD(a0),d6
	bne .phase
	move.l TR_COMMAND(a1),d4
	cmp.l TS_COMMAND(a0),d4
	bne .phase
	bsr scheduler_check
	tst.l d0
	bmi .done
	movea.l d5,a0
	movea.l TS_COMMANDS(a0),a0
	lea SE_WORK_COMMAND(a5),a1
	move.l d4,d0
	moveq #0,d1
	bsr commands_peek
	tst.l d0
	bmi .done
	bne .phase
	movea.l d5,a0
	tst.w TS_DUE(a0)
	beq .commands_ready
	movea.l TS_COMMANDS(a0),a0
	move.l d4,d0
	moveq #1,d1
	bsr commands_peek
	tst.l d0
	bmi .done
	bne .phase
.commands_ready:
	movea.l d5,a0
	movea.l TS_CLOCK(a0),a2
	movea.l SE_OWNER(a6),a0
	move.w TC_RATE(a2),d0
	cmp.w EP_DELAY+CD_RATE(a0),d0
	bne .phase
	movea.l a5,a1
	moveq #EP_SIZE/16-1,d1
.state:
	REPT 4
	move.l (a0)+,(a1)+
	ENDR
	dbf d1,.state
	REPT EP_SIZE/4-(EP_SIZE/16)*4
	move.l (a0)+,(a1)+
	ENDR
	IFNE EP_SIZE&2
	move.w (a0)+,(a1)+
	ENDC
	move.w EP_DONE(a5),d0
	cmp.w EP_SPAN(a5),d0
	bne .ongoing
	; Clock has consumed this field. Recover phase BEFORE it, then choose
	; the number of delivered fields to the next deadline, including this one.
	moveq #0,d0
	move.w TC_PHASE(a2),d0
	subq.w #3,d0
	bpl .previous_phase
	add.w TC_RATE(a2),d0
.previous_phase:
	cmpi.w #2,d0
	bhi .phase
	moveq #0,d1
	move.w TC_RATE(a2),d1
	sub.w d0,d1
	addq.w #2,d1
	divu.w #3,d1
	moveq #0,d0
	move.w d1,d0
	move.l d7,d1
	movea.l a5,a0
	movea.l SE_PLAYER(a6),a1
	bsr endpoint_player_begin
	tst.l d0
	bne .done
.ongoing:
	cmp.w EP_TICK(a5),d7
	bne .phase
	; A completed endpoint and a world deadline must be the same field.
	move.w EP_DONE(a5),d0
	addq.w #1,d0
	cmp.w EP_SPAN(a5),d0
	bhi .phase
	seq d1
	andi.w #1,d1
	movea.l d5,a0
	cmp.w TS_DUE(a0),d1
	bne .phase
	movea.l a5,a0
	movea.l SE_PLAYER(a6),a1
	movea.l SE_STAGES(a6),a2
	movea.l SE_SINE(a6),a3
	movea.l SE_PACKET(a6),a4
	move.l d6,d0
	; Basic contexts have no optional extension. The ground context owns
	; a cache pointer; preserve the private transaction base across dispatch.
	move.l a5,-(sp)
	tst.w SE_WORK_SIZE(a5)
	beq .uncached
	movea.l SE_CACHE(a6),a5
	bra .player_step
.uncached:
	suba.l a5,a5
.player_step:
	bsr endpoint_player_step_private
	movea.l (sp)+,a5
	tst.l d0
	bne .done
	tst.w SE_WORK_SIZE(a5)
	beq .health
	movea.l d5,a0
	tst.w TS_DUE(a0)
	beq .health
	movea.l a5,a0
	lea SE_WORK_PLAYER(a5),a1
	movea.l SE_STAGES(a6),a2
	movea.l SE_GROUND(a6),a3
	movea.l SE_EVENT(a6),a4
	bsr endpoint_ground_resolve
	tst.l d0
	bmi .done
	move.w #1,SE_WORK_SIZE+2(a5)
.health:
	movea.l d5,a0
	bsr scheduler_check
	tst.l d0
	bmi .done
	movea.l a5,a0
	movea.l SE_OWNER(a6),a1
	moveq #EP_SIZE/16-1,d1
.publish_state:
	REPT 4
	move.l (a0)+,(a1)+
	ENDR
	dbf d1,.publish_state
	REPT EP_SIZE/4-(EP_SIZE/16)*4
	move.l (a0)+,(a1)+
	ENDR
	IFNE EP_SIZE&2
	move.w (a0)+,(a1)+
	ENDC
	movea.l SE_PLAYER(a6),a1
	lea SE_WORK_PLAYER(a5),a0
	moveq #MP_RECORD_SIZE/16-1,d1
.publish_player:
	REPT 4
	move.l (a0)+,(a1)+
	ENDR
	dbf d1,.publish_player
	REPT MP_RECORD_SIZE/4-(MP_RECORD_SIZE/16)*4
	move.l (a0)+,(a1)+
	ENDR
	IFNE MP_RECORD_SIZE&2
	move.w (a0)+,(a1)+
	ENDC
	move.l d6,SE_FIELD(a6)
	move.w #1,SE_COMMITTED(a6)
	movea.l d5,a0
	bsr scheduler_player_done
	bra .done
.phase:
	moveq #-3,d0
.done:
	tst.w SE_WORK_SIZE+2(a5)
	beq .restore
	tst.w SE_COMMITTED(a6)
	bne .restore
	movea.l SE_EVENT(a6),a0
	clr.l (a0)
.restore:
	adda.w #SE_WORK_SIZE+4,sp
	movem.l (sp)+,d1-d7/a0-a6
	rts
