; Hybrid world clock, 68000-compatible, with caller-owned state.
; Not installed in the game yet: the native adapter must consume field history
; and run a world tick immediately when clock_field returns 1, before consuming
; the next field. See TIMING_DESIGN.md for ownership and integration gates.
;
; All entry points preserve d1-d7/a0-a6. d0 and CCR are results.
; Call from the foreground consumer, never from the VBL producer.

TC_LAST       = 0               ; last consumed active field, unsigned long
TC_FIELDS     = 4               ; lifetime accepted fields
TC_TICKS      = 8               ; lifetime world deadlines
TC_DROPPED    = 12              ; clock units discarded at explicit rebases
TC_REBASES    = 16
TC_PHASE      = 20              ; remainder, 0 <= phase < rate
TC_RATE       = 22              ; 50 or 60, selected from display timing
TC_ACTIVE     = 24
TC_FAULT      = 26              ; discontinuous history: explicit rebase required
TC_STATE_SIZE       = 28

; a0=state, d0=field epoch, d1=display field rate.
; Fresh state, return 0; invalid rate returns -1 without writing.
clock_init:
	cmpi.l #50,d1
	beq .valid
	cmpi.l #60,d1
	bne .bad
.valid:
	move.l d0,TC_LAST(a0)
	clr.l TC_FIELDS(a0)
	clr.l TC_TICKS(a0)
	clr.l TC_DROPPED(a0)
	clr.l TC_REBASES(a0)
	clr.w TC_PHASE(a0)
	move.w d1,TC_RATE(a0)
	move.w #1,TC_ACTIVE(a0)
	clr.w TC_FAULT(a0)
	moveq #0,d0
	rts
.bad:
	moveq #-1,d0
	rts

; d0=next active field stamp. Return 1 at a world deadline, 0 otherwise,
; -1 for a missing/duplicate/out-of-order sample, -2 while paused.
; The unsigned field stamp may wrap. A fault cannot silently resume.
clock_field:
	tst.w TC_ACTIVE(a0)
	beq .paused
	tst.w TC_FAULT(a0)
	bne .bad
	move.l d1,-(sp)
	move.l d0,d1
	sub.l TC_LAST(a0),d1
	cmpi.l #1,d1
	bne .gap
	move.l d0,TC_LAST(a0)
	addq.l #1,TC_FIELDS(a0)
	move.w TC_PHASE(a0),d1
	addq.w #3,d1
	cmp.w TC_RATE(a0),d1
	blo .not_due
	sub.w TC_RATE(a0),d1
	move.w d1,TC_PHASE(a0)
	addq.l #1,TC_TICKS(a0)
	move.l (sp)+,d1
	moveq #1,d0
	rts
.not_due:
	move.w d1,TC_PHASE(a0)
	move.l (sp)+,d1
	moveq #0,d0
	rts
.gap:
	move.l (sp)+,d1
	move.w #1,TC_FAULT(a0)
.bad:
	moveq #-1,d0
	rts
.paused:
	moveq #-2,d0
	rts

clock_pause:
	clr.w TC_ACTIVE(a0)
	moveq #0,d0
	rts

; d0=new epoch. Preserve lifetime diagnostics, report the discarded phase.
; The caller separately counts unread/lost history fields. Rebase only at an
; explicit modal/recovery boundary, not whenever a render is late.
clock_rebase:
	move.l d0,TC_LAST(a0)
	moveq #0,d0
	move.w TC_PHASE(a0),d0
	add.l d0,TC_DROPPED(a0)
	addq.l #1,TC_REBASES(a0)
	clr.w TC_PHASE(a0)
	clr.w TC_FAULT(a0)
	move.w #1,TC_ACTIVE(a0)
	rts
