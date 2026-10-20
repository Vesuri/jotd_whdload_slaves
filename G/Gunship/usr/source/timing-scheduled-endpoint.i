; Airborne scheduler bridge for endpoint-player. Not installed.
SE_OWNER equ 0
SE_PLAYER equ 4
SE_STAGES equ 8
SE_SINE equ 12
SE_PACKET equ 16
SE_SCHEDULER equ 20
SE_FIELD equ 24
SE_COMMITTED equ 28
SE_SIZE equ 30
SE_WORK_PLAYER equ EP_SIZE
SE_WORK_COMMAND equ EP_SIZE+MP_RECORD_SIZE
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
	movem.l d1-d7/a0-a6,-(sp)
	suba.w #SE_WORK_SIZE,sp
	movea.l sp,a5
	movea.l a0,a6
	clr.w SE_COMMITTED(a6)
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
	moveq #EP_SIZE/2-1,d1
.state:
	move.w (a0)+,(a1)+
	dbf d1,.state
	movea.l SE_PLAYER(a6),a0
	moveq #MP_RECORD_SIZE/2-1,d1
.player:
	move.w (a0)+,(a1)+
	dbf d1,.player
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
	lea SE_WORK_PLAYER(a5),a1
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
	lea SE_WORK_PLAYER(a5),a1
	movea.l SE_STAGES(a6),a2
	movea.l SE_SINE(a6),a3
	movea.l SE_PACKET(a6),a4
	move.l d6,d0
	bsr endpoint_player_step
	tst.l d0
	bne .done
	movea.l d5,a0
	bsr scheduler_check
	tst.l d0
	bmi .done
	movea.l a5,a0
	movea.l SE_OWNER(a6),a1
	moveq #EP_SIZE/2-1,d1
.publish_state:
	move.w (a0)+,(a1)+
	dbf d1,.publish_state
	movea.l SE_PLAYER(a6),a1
	moveq #MP_RECORD_SIZE/2-1,d1
.publish_player:
	move.w (a0)+,(a1)+
	dbf d1,.publish_player
	move.l d6,SE_FIELD(a6)
	move.w #1,SE_COMMITTED(a6)
	movea.l d5,a0
	bsr scheduler_player_done
	bra .done
.phase:
	moveq #-3,d0
.done:
	adda.w #SE_WORK_SIZE,sp
	movem.l (sp)+,d1-d7/a0-a6
	rts
