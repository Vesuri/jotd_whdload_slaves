; Split player motion with private native-duration control history.
; Requires player-boundary and control-delay. Standalone, not installed.
; Prefix is the ordinary ground-compatible PB candidate.
PD_DELAY equ PB_SIZE
PD_BASE equ PD_DELAY+CD_SIZE
PD_BIND_DELAY equ PD_BASE+CD_SIZE
PD_BIND_SHADOW equ PD_BIND_DELAY+4
PD_BIND_PLAYER equ PD_BIND_SHADOW+4
PD_PHASE equ PD_BIND_PLAYER+4
PD_SIZE equ PD_PHASE+2

; Ordinary prepare arguments, plus a6=delay state, d1=field stamp.
; a5 must hold PD_SIZE bytes. Return 0/-1, preserve other registers.
; No authoritative state writes. On success ground may edit the PB prefix.
player_boundary_delay_prepare:
	movem.l d1-d7/a0-a6,-(sp)
	clr.w PD_PHASE(a5)
	clr.w PB_PHASE(a5)
	move.l a6,PD_BIND_DELAY(a5)
	move.l a0,PD_BIND_SHADOW(a5)
	move.l a1,PD_BIND_PLAYER(a5)
	move.w AT_RATE(a0),d2
	cmp.w CD_RATE(a6),d2
	bne .bad_no_stack
	move.l d0,d6
	move.l d1,d7
	suba.w #PS_SIZE,sp
	movea.l sp,a1
	moveq #PS_SIZE/2-1,d1
.copy_shadow:
	move.w (a0)+,(a1)+
	dbf d1,.copy_shadow
	movea.l a6,a0
	lea PD_BASE(a5),a1
	moveq #CD_SIZE/2-1,d1
.copy_base:
	move.w (a0)+,(a1)+
	dbf d1,.copy_base
	movea.l a6,a0
	lea PD_DELAY(a5),a1
	moveq #CD_SIZE/2-1,d1
.copy_delay:
	move.w (a0)+,(a1)+
	dbf d1,.copy_delay
	lea PD_DELAY(a5),a0
	move.l d7,d0
	move.w 2(a4),d1
	ext.l d1
	bsr control_delay_step
	tst.l d1
	bne .bad
	move.w d0,AT_PREVIOUS_Y(sp)
	movea.l sp,a0
	movea.l PD_BIND_PLAYER(a5),a1
	move.l d6,d0
	bsr player_boundary_prepare
	tst.l d0
	bne .done
	move.w #1,PD_PHASE(a5)
	bra .done
.bad:
	moveq #-1,d0
.done:
	adda.w #PS_SIZE,sp
	bra .restore
.bad_no_stack:
	moveq #-1,d0
.restore:
	movem.l (sp)+,d1-d7/a0-a6
	rts

; Ordinary complete arguments, plus a6=delay state, a5=PD candidate.
; Validate binding and unchanged base history before publishing motion.
; Any completion attempt consumes the prepared transaction. Failure cannot
; publish history, player or shadow; deferred ground effects remain external.
player_boundary_delay_complete:
	movem.l d1-d2/a0-a6,-(sp)
	cmpi.w #1,PD_PHASE(a5)
	bne .bad
	clr.w PD_PHASE(a5)
	cmpa.l PD_BIND_DELAY(a5),a6
	bne .invalidate
	cmpa.l PD_BIND_SHADOW(a5),a0
	bne .invalidate
	cmpa.l PD_BIND_PLAYER(a5),a1
	bne .invalidate
	move.l a0,-(sp)
	move.l a1,-(sp)
	movea.l a6,a0
	lea PD_BASE(a5),a1
	moveq #CD_SIZE/2-1,d1
.compare:
	move.w (a0)+,d2
	cmp.w (a1)+,d2
	bne .changed
	dbf d1,.compare
	movea.l (sp)+,a1
	movea.l (sp)+,a0
	bsr player_boundary_complete
	tst.l d0
	bne .invalidate
	lea PD_DELAY(a5),a0
	movea.l a6,a1
	moveq #CD_SIZE/2-1,d1
.publish:
	move.w (a0)+,(a1)+
	dbf d1,.publish
	bra .done
.changed:
	movea.l (sp)+,a1
	movea.l (sp)+,a0
.invalidate:
	clr.w PB_PHASE(a5)
.bad:
	moveq #-1,d0
.done:
	movem.l (sp)+,d1-d2/a0-a6
	rts
