; Combined player candidate exposing the native height/contact boundary.
; Requires player-step definitions. Standalone; no world scheduling installed.
PB_KINEMATICS equ AT_SIZE
PB_PLAYER equ PB_KINEMATICS+KN_PLAYER
PB_PHASE equ PB_KINEMATICS+KN_PHASE
PB_WORK equ PB_KINEMATICS+KN_SCRATCH
PB_TICK equ PB_WORK+PS_SCRATCH
PB_SIZE equ PB_TICK+2

; a0=PS shadow, a1=player, a2=stages, a3=sine, a4=control/impulse packet,
; a5=separate PB_SIZE-byte candidate, d0=logical interval tick (0..65535).
; Return 0/-1; preserve others. Original shadow/player are never changed.
; Candidate starts with contiguous PS shadow/player for ground evaluation.
; Caller owns serialized lifetime, validated code and non-overlapping storage.
player_boundary_prepare:
	movem.l d1-d7/a0-a6,-(sp)
	movea.l a5,a6
	clr.w PB_PHASE(a6)
	cmpi.l #65535,d0
	bhi .bad
	move.l d0,d4
	move.l a4,d5
	move.l a2,d6
	move.l a3,d7
	lea PB_WORK(a6),a4
	movea.l a4,a2
	moveq #PS_SIZE/2-1,d1
.state:
	move.w (a0)+,(a2)+
	dbf d1,.state
	moveq #MP_RECORD_SIZE/2-1,d1
.player:
	move.w (a1)+,(a2)+
	dbf d1,.player
	move.w PS_PLAYER+$0c(a4),PB_TICK(a6)
	move.w d4,PS_PLAYER+$0c(a4)
	move.w AT_RATE(a4),d0
	cmp.w PS_KINEMATICS+FR_RATE(a4),d0
	bne .bad
	movea.l a4,a0
	lea PS_PLAYER(a4),a1
	bsr attitude_pitch_clamp
	tst.l d0
	bne .bad
	movea.l d5,a2
	move.w (a2),d0
	ext.l d0
	move.w 2(a2),d1
	ext.l d1
	move.w 4(a2),d2
	ext.l d2
	move.w 6(a2),d3
	ext.l d3
	bsr attitude_step_impulses
	tst.l d0
	bne .bad
	movea.l a4,a0
	movea.l a6,a1
	moveq #AT_SIZE/2-1,d1
.attitude:
	move.w (a0)+,(a1)+
	dbf d1,.attitude
	move.w 8(a2),d0
	ext.l d0
	lea PS_KINEMATICS(a4),a0
	lea PS_PLAYER(a4),a1
	movea.l d6,a2
	movea.l d7,a3
	lea PB_KINEMATICS(a6),a4
	bsr kinematics_prepare
	bra .done
.bad:
	moveq #-1,d0
.done:
	movem.l (sp)+,d1-d7/a0-a6
	rts

; Same pointers as prepare; packet a4/d0 input ignored, candidate in a5.
; Finish privately, restore the authoritative tick, then publish the complete
; PS shadow/player. A failed or repeated completion publishes nothing.
; Deferred ground events must be committed separately ONLY after success.
player_boundary_complete:
	movem.l d1-d7/a0-a6,-(sp)
	movea.l a0,a6
	move.l a1,d5
	movea.l a5,a4
	lea PB_WORK+PS_KINEMATICS(a5),a0
	lea PB_WORK+PS_PLAYER(a5),a1
	adda.w #PB_KINEMATICS,a4
	bsr kinematics_complete
	tst.l d0
	bne .done
	move.w PB_TICK(a5),PB_WORK+PS_PLAYER+$0c(a5)
	movea.l a5,a0
	lea PB_WORK(a5),a1
	moveq #AT_SIZE/2-1,d1
.attitude:
	move.w (a0)+,(a1)+
	dbf d1,.attitude
	lea PB_WORK(a5),a0
	moveq #PS_SIZE/2-1,d1
.state:
	move.w (a0)+,(a6)+
	dbf d1,.state
	movea.l d5,a1
	moveq #MP_RECORD_SIZE/2-1,d1
.player:
	move.w (a0)+,(a1)+
	dbf d1,.player
	moveq #0,d0
.done:
	movem.l (sp)+,d1-d7/a0-a6
	rts
