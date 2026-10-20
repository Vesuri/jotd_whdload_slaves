; Native script-modal continuation. Requires lifecycle and world-body.
; Prepared stable bindings; not installed in production.
TM_SCHEDULER equ 0
TM_WORLD equ 4
TM_INTERPRETER equ 8
TM_PHASE equ 12 ; 0 ready, 1 suspended, 2 running, 3 returned/error, 4 done, 5 ended
TM_SIZE equ 14

; a0=TM, a1=TS, a2=WB, a3=hunk 0. Return 0/-1, preserve other registers.
; Initialize only at a new lifecycle admission, never to retry partial work.
timing_modal_prepare:
	movem.l a3,-(sp)
	adda.l #$8050,a3
	cmpi.l #$4a2d0053,(a3)
	bne .bad
	cmpi.l #$6f00014e,4(a3)
	bne .bad
	cmpi.l #$532d0054,8(a3)
	bne .bad
	cmpi.l #$66000146,12(a3)
	bne .bad
	move.l a1,TM_SCHEDULER(a0)
	move.l a2,TM_WORLD(a0)
	move.l a3,TM_INTERPRETER(a0)
	clr.w TM_PHASE(a0)
	moveq #0,d0
	bra .done
.bad:
	moveq #-1,d0
.done:
	movem.l (sp)+,a3
	rts

; a0=TM, producer/consumers excluded by caller. Return 0/-1/-3.
; Pending ground events must already be committed. Retain due world ownership.
timing_modal_suspend:
	movem.l d1-d7/a0-a6,-(sp)
	movea.l a0,a4
	tst.w TM_PHASE(a4)
	bne .phase
	bsr timing_modal_validate
	tst.l d0
	bne .done
	movea.l TM_SCHEDULER(a4),a0
	bsr scheduler_check
	tst.l d0
	bne .done
	bsr timing_suspend
	move.w #1,TM_PHASE(a4)
	bra .done
.phase:
	moveq #-3,d0
.done:
	movem.l (sp)+,d1-d7/a0-a6
	rts

; a0=TM. Call AFTER restoring interrupts; sampling owners remain disabled.
; Runs native +8050, then only the unexecuted script body/world tail.
; Return 0 completed, 3 flight ended, -1 failure, -3 invalid phase.
; Sampling stays off. Reset external caches and call timing_resume separately.
timing_modal_run:
	movem.l d1-d7/a0-a6,-(sp)
	movea.l a0,a4
	cmpi.w #1,TM_PHASE(a4)
	bne .phase
	bsr timing_modal_validate
	tst.l d0
	bne .done
	movea.l TM_SCHEDULER(a4),a0
	movea.l TS_CLOCK(a0),a1
	tst.w TC_ACTIVE(a1)
	bne .phase
	movea.l TS_HISTORY(a0),a1
	tst.w TH_ACTIVE(a1)
	bne .phase
	movea.l TS_COMMANDS(a0),a1
	tst.w CQ_ACTIVE(a1)
	bne .phase
	move.w #2,TM_PHASE(a4)
	movea.l TM_WORLD(a4),a0
	movea.l WB_PLAYER(a0),a5
	movea.l TM_INTERPRETER(a4),a0
	; Native interpreter may clobber every working register.
	move.l a4,-(sp)
	jsr (a0)
	movea.l (sp)+,a4
	move.w #3,TM_PHASE(a4)
	movea.l TM_WORLD(a4),a0
	bsr world_body_resume
	tst.l d0
	beq .complete
	cmpi.l #3,d0
	bne .done
.complete:
	move.l d0,d7
	move.w #4,TM_PHASE(a4)
	tst.l d7
	beq .ack
	move.w #5,TM_PHASE(a4)
.ack:
	movea.l TM_SCHEDULER(a4),a0
	; This counts committed work before reporting inactive upstream owners.
	; Resume clears that expected fault; never replay the world to repair it.
	bsr scheduler_world_done
	move.l d7,d0
	bra .done
.phase:
	moveq #-3,d0
.done:
	movem.l (sp)+,d1-d7/a0-a6
	rts

; Internal: a4=TM; validate all world bindings before any interpreter effects.
timing_modal_validate:
	movea.l TM_SCHEDULER(a4),a0
	cmpi.w #2,TS_STATE(a0)
	bne .phase
	cmpi.w #1,TS_DUE(a0)
	bne .phase
	movea.l TM_WORLD(a4),a6
	cmpi.w #1,WB_PHASE(a6)
	bne .phase
	bsr world_body_validate
	tst.l d0
	bne .done
	movea.l WB_PLAYER(a6),a0
	tst.b $53(a0)
	ble .phase
	cmpi.b #1,$54(a0)
	bne .phase
	moveq #0,d0
.done:
	rts
.phase:
	moveq #-3,d0
	rts
