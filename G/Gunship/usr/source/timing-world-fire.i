; Build native-equivalent fire flags for one delivered world deadline.
; Requires timing-scheduler.i. Standalone; native weapon routing not installed.
; Native +04e4c..+04e88 collapses two rising-edge counters to byte booleans.
; Held buttons are retained separately: ORing them here would invent repeat fire.
;
; a0=scheduler, a1=private two-byte output, return 0/-1/-3, preserve others.
; Require world phase and healthy upstream owners. Does not acknowledge a tick,
; clear accumulated edges, write native input latches or consume held state.
; Caller must invoke weapon work once, then acknowledge the completed world.
; Output is private and must be discarded on any failed world preparation.
world_fire_prepare:
	cmpi.w #2,TS_STATE(a0)
	bne .phase
	movem.l d1-d2,-(sp)
	bsr scheduler_check
	tst.l d0
	bmi .done
	moveq #0,d1
	moveq #0,d2
	btst #0,TS_EDGES+1(a0)
	beq .second
	moveq #1,d1
.second:
	btst #1,TS_EDGES+1(a0)
	beq .publish
	moveq #1,d2
.publish:
	move.b d1,(a1)
	move.b d2,1(a1)
	; A producer may have faulted while the private packet was built.
	bsr scheduler_check
.done:
	movem.l (sp)+,d1-d2
	rts
.phase:
	moveq #-3,d0
	rts
