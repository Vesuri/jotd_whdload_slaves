; Diagnostic trace of discrete requests issued by the simulation sound gate.
; This measures dispatches, not the timer-driven audio sequencer or audibility.
STEP_EVENT_SLOTS = 1024
	IFD VERIFY_C_SEED_ATTACK
; Synthetic boundary fixture: an armed player starts the active attack phase.
; Uses native action, pose selection and sound dispatch; never a normal option.
step_event_seed_attack:
	move.l step_stats+8(pc),d0
	cmpi.l #501,d0
	bne .done
	ori.b #$10,$a5dc9
	andi.b #$bf,$a5dc9
	ori.b #2,$a5dcb
	clr.b $a5dcc
	move.b #1,$a5dcd
	move.b #1,$a59d6
.done:
	rts
	ENDC
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
public_ref_155 equ *-4
step_event_stop:
	move.w sr,-(a7)
	movem.l d0-d2/a0,-(a7)
	moveq #2,d1
	moveq #0,d0 ; this stop request has no sound-number parameter
	bsr step_event_log
	movem.l (a7)+,d0-d2/a0
	move.w (a7)+,ccr
	jmp $b5184
public_ref_156 equ *-4
step_event_primary:
	move.w sr,-(a7)
	movem.l d0-d2/a0,-(a7)
	moveq #3,d1
	bsr step_event_log
	movem.l (a7)+,d0-d2/a0
	move.w (a7)+,ccr
	jmp $b507e
public_ref_157 equ *-4
step_event_secondary:
	move.w sr,-(a7)
	movem.l d0-d2/a0,-(a7)
	moveq #4,d1
	bsr step_event_log
	movem.l (a7)+,d0-d2/a0
	move.w (a7)+,ccr
	jmp $b507e
public_ref_158 equ *-4
step_event_siren:
	move.w sr,-(a7)
	movem.l d0-d2/a0,-(a7)
	moveq #5,d1
	bsr step_event_log
	movem.l (a7)+,d0-d2/a0
	move.w (a7)+,ccr
	jmp $b5052
public_ref_159 equ *-4
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
