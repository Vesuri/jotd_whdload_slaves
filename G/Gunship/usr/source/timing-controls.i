; Decode one already-copied history record into a player-step input packet.
; Requires timing-history.i. Standalone; native installation pending.
; a0=TH_RECORD_SIZE record, a1=10-byte player-step packet.
; d0=0 success/-1 unsupported direction; other registers preserved.
; Native +0544a reads the LOW BYTE of each sampled long, not its full value.
; Samples already include native mouse filtering. Never integrate raw deltas
; again here. Scheduler owns field ordering/acknowledgement and world edges.
; Ordinary fields start with zero world impulses; world owner may then supply
; eligible impulses once. Replay controls require their separate native path.
controls_from_history:
	movem.l d1-d2,-(sp)
	move.b TR_X+3(a0),d1
	ext.w d1
	cmpi.w #-1,d1
	blt .bad
	cmpi.w #1,d1
	bgt .bad
	move.b TR_Y+3(a0),d2
	ext.w d2
	cmpi.w #-1,d2
	blt .bad
	cmpi.w #1,d2
	bgt .bad
	move.w d1,(a1)
	move.w d2,2(a1)
	clr.l 4(a1)
	clr.w 8(a1)
	moveq #0,d0
	bra .done
.bad:
	moveq #-1,d0
.done:
	movem.l (sp)+,d1-d2
	rts
