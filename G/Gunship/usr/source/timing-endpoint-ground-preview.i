; Whole-native-tick preview with ground in its original arithmetic order.
; Requires player-boundary and ground-deferred. Standalone, not installed.
EG_CLONE equ 0
EG_EVENT equ 4
EG_SIZE equ 8

; a0=PS state initialized at rate 3, a1=PRIVATE candidate player,
; a2=prepared stages, a3=sine helper, a4=decoded packet,
; a6=EG_SIZE binding (deferred ground clone, its bound event), d0=logical tick.
; Return 0/-1; preserve others. On success player/state contain a complete
; native tick and event is ready (possibly empty). No native notifications.
; On rejection player/state are unchanged and an initially empty event stays
; empty. An already pending event rejects without overwriting it.
; Caller owns event/clone binding, validated buffers/code, serialization and
; cache synchronization. Commit effects only after authoritative publication.
; This is candidate construction, NOT a decision to ground the distributed
; player. Deadline contact selection and fractional reset remain owner work.
endpoint_ground_preview:
	movem.l d1-d7/a0-a6,-(sp)
	cmpi.w #3,AT_RATE(a0)
	bne .bad_no_stack
	cmpi.w #3,PS_KINEMATICS+FR_RATE(a0)
	bne .bad_no_stack
	movea.l EG_EVENT(a6),a5
	tst.l (a5)
	bne .bad_no_stack
	move.l EG_CLONE(a6),d1
	move.l a5,d2
	move.l a0,d3
	move.l a1,d4
	move.l a2,d5
	move.l a3,d6
	move.l a4,d7
	suba.w #PB_SIZE,sp
	movea.l sp,a5
	bsr player_boundary_prepare
	tst.l d0
	bne .reject
	movea.l a5,a0
	lea PB_PLAYER(a5),a1
	movea.l d1,a2
	movea.l d2,a3
	moveq #0,d0
	move.w PB_KINEMATICS+KN_MOVEMENT+MV_WAS_AIRBORNE(a5),d0
	bsr ground_deferred_step
	tst.l d0
	bmi .reject
	movea.l d3,a0
	movea.l d4,a1
	movea.l d5,a2
	movea.l d6,a3
	movea.l d7,a4
	bsr player_boundary_complete
	tst.l d0
	beq .done
.reject:
	movea.l d2,a0
	clr.l (a0)
	moveq #-1,d0
.done:
	adda.w #PB_SIZE,sp
	bra .restore
.bad_no_stack:
	moveq #-1,d0
.restore:
	movem.l (sp)+,d1-d7/a0-a6
	rts
