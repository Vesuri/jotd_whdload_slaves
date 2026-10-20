; Scheduler/player bridge. Standalone; native command/world routing pending.
FP_SHADOW equ 0
FP_PLAYER equ 4
FP_STAGES equ 8
FP_SINE equ 12
FP_PACKET equ 16
FP_CANDIDATE equ 20
FP_SCHEDULER equ 24
FP_FIELD equ 28
FP_COMMAND equ 32
FP_BOUND equ 36
FP_COMMITTED equ 38
FP_SIZE equ 40
; Delayed entry takes the original context plus one explicit history pointer.
; Legacy entry never reads this extension. Delayed candidates require PD_SIZE.
FP_DELAY equ FP_SIZE
FP_DELAY_SIZE equ FP_SIZE+4
	IFND CD_SIZE
	include "timing-control-delay.i"
	ENDC
	IFND PD_SIZE
	include "timing-player-boundary-delay.i"
	ENDC

; Caller initializes six pointers and zeros the remaining context.
; a0=context, a1=scheduler, a2=delivered private record, d0=interval tick.
; Packet decoding/world impulses must already be resolved. The player command
; reader must have drained this cutoff; retained commands reject preparation.
; Return 0 prepared, -1 fault/player failure, -3 phase/identity/rate mismatch.
; No scheduler acknowledgement or original-player mutation here.
field_player_prepare:
	move.l d1,-(sp)
	moveq #0,d1
	bsr field_player_prepare_common
	move.l (sp)+,d1
	rts

; Same API, FP_DELAY must point to initialized native-duration control history.
; Uses the delivered field stamp, not render time, for history advancement.
field_player_prepare_delayed:
	move.l d1,-(sp)
	moveq #1,d1
	bsr field_player_prepare_common
	move.l (sp)+,d1
	rts

field_player_prepare_common:
	movem.l d1-d7/a0-a6,-(sp)
	suba.w #12,sp
	move.l d1,8(sp)
	movea.l a0,a6
	move.l d0,d4
	tst.w FP_BOUND(a6)
	bne .phase
	clr.w FP_COMMITTED(a6)
	tst.l 8(sp)
	beq .context_ok
	tst.l FP_DELAY(a6)
	beq .phase
.context_ok:
	cmpi.w #1,TS_STATE(a1)
	bne .phase
	move.l TR_FIELD(a2),d6
	cmp.l TS_FIELD(a1),d6
	bne .phase
	move.l TR_COMMAND(a2),d7
	cmp.l TS_COMMAND(a1),d7
	bne .phase
	movea.l FP_SHADOW(a6),a3
	movea.l TS_CLOCK(a1),a4
	move.w TC_RATE(a4),d1
	cmp.w AT_RATE(a3),d1
	bne .phase
	move.l a1,d5
	movea.l a1,a0
	bsr scheduler_check
	tst.l d0
	bmi .done
	; Inspect without releasing a retained command or applying its effects.
	; A field cannot advance past an ordinary command or lifecycle boundary.
	movea.l d5,a0
	movea.l TS_COMMANDS(a0),a0
	movea.l sp,a1
	move.l d7,d0
	moveq #0,d1
	bsr commands_peek
	tst.l d0
	bmi .done
	bne .phase
	movea.l FP_SHADOW(a6),a0
	movea.l FP_PLAYER(a6),a1
	movea.l FP_STAGES(a6),a2
	movea.l FP_SINE(a6),a3
	movea.l FP_PACKET(a6),a4
	movea.l FP_CANDIDATE(a6),a5
	move.l d4,d0
	tst.l 8(sp)
	beq .ordinary
	move.l a6,-(sp)
	movea.l FP_DELAY(a6),a6
	move.l d6,d1
	bsr player_boundary_delay_prepare
	movea.l (sp)+,a6
	bra .prepared
.ordinary:
	bsr player_boundary_prepare
.prepared:
	tst.l d0
	bne .done
	move.l d5,FP_SCHEDULER(a6)
	move.l d6,FP_FIELD(a6)
	move.l d7,FP_COMMAND(a6)
	move.w #1,FP_BOUND(a6)
	tst.l 8(sp)
	beq .done
	move.w #2,FP_BOUND(a6)
	bra .done
.phase:
	moveq #-3,d0
.done:
	adda.w #12,sp
	movem.l (sp)+,d1-d7/a0-a6
	rts

; a0=context. FP_BOUND=1 selects ordinary completion, 2 selects delayed
; history completion. Ground may be evaluated privately between the two calls.
; Return scheduler_player_done result: 0 ready, 1 world due, -1 fault;
; -3 invalid binding/phase. A failed candidate is not acknowledged.
; FP_COMMITTED distinguishes a fault AFTER publication from rejection before
; it. Deferred events follow that flag; recovery must account for applied work.
; Caller serializes context, candidate and scheduler. Producers may interrupt.
field_player_complete:
	movem.l d1-d7/a0-a6,-(sp)
	movea.l a0,a6
	cmpi.w #1,FP_BOUND(a6)
	beq .bound
	cmpi.w #2,FP_BOUND(a6)
	bne .phase
.bound:
	movea.l FP_SCHEDULER(a6),a0
	cmpi.w #1,TS_STATE(a0)
	bne .reject_phase
	move.l FP_FIELD(a6),d1
	cmp.l TS_FIELD(a0),d1
	bne .reject_phase
	move.l FP_COMMAND(a6),d1
	cmp.l TS_COMMAND(a0),d1
	bne .reject_phase
	bsr scheduler_check
	tst.l d0
	bmi .reject
	movea.l FP_SHADOW(a6),a0
	movea.l FP_PLAYER(a6),a1
	movea.l FP_STAGES(a6),a2
	movea.l FP_SINE(a6),a3
	movea.l FP_PACKET(a6),a4
	movea.l FP_CANDIDATE(a6),a5
	cmpi.w #2,FP_BOUND(a6)
	bne .ordinary
	move.l a6,-(sp)
	movea.l FP_DELAY(a6),a6
	bsr player_boundary_delay_complete
	movea.l (sp)+,a6
	bra .completed
.ordinary:
	bsr player_boundary_complete
.completed:
	tst.l d0
	bne .reject
	clr.w FP_BOUND(a6)
	move.w #1,FP_COMMITTED(a6)
	movea.l FP_SCHEDULER(a6),a0
	bsr scheduler_player_done
	bra .done
.reject_phase:
	moveq #-3,d0
.reject:
	movea.l FP_CANDIDATE(a6),a0
	cmpi.w #2,FP_BOUND(a6)
	bne .invalidate
	clr.w PD_PHASE(a0)
.invalidate:
	clr.w FP_BOUND(a6)
	clr.w PB_PHASE(a0)
	bra .done
.phase:
	moveq #-3,d0
.done:
	movem.l (sp)+,d1-d7/a0-a6
	rts
