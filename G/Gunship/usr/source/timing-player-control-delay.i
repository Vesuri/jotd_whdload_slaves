; Transactional continuous player + native-duration control history.
; Requires player-step and control-delay. Standalone, no production hook.
; a0=PS state, a1=player, a2=stages, a3=sine, a4=packet, a5=CD state,
; d0=field stamp. Player's logical tick parity must already be set by caller.
; Return 0/-1, preserve others. Failed motion cannot consume control history.
; This entry excludes ground/world effects, like player_step; the split ground
; and scheduler adapters still need the same private history publication.
player_step_delayed:
	movem.l d1-d7/a0-a6,-(sp)
	move.w AT_RATE(a0),d1
	cmp.w CD_RATE(a5),d1
	bne .bad_no_stack
	move.l a0,d6
	move.l a5,d7
	move.l a1,d2
	move.l a2,d3
	move.l a3,d4
	move.l a4,d5
	suba.w #PS_SIZE+CD_SIZE,sp
	movea.l sp,a6
	movea.l a6,a1
	moveq #PS_SIZE/2-1,d1
.copy_player_state:
	move.w (a0)+,(a1)+
	dbf d1,.copy_player_state
	movea.l a5,a0
	moveq #CD_SIZE/2-1,d1
.copy_delay:
	move.w (a0)+,(a1)+
	dbf d1,.copy_delay
	lea PS_SIZE(a6),a0
	movea.l d5,a1
	move.w 2(a1),d1
	ext.l d1
	bsr control_delay_step
	tst.l d1
	bne .bad
	move.w d0,AT_PREVIOUS_Y(a6)
	movea.l a6,a0
	movea.l d2,a1
	movea.l d3,a2
	movea.l d4,a3
	movea.l d5,a4
	bsr player_step
	tst.l d0
	bne .done
	movea.l a6,a0
	movea.l d6,a1
	moveq #PS_SIZE/2-1,d1
.publish_player_state:
	move.w (a0)+,(a1)+
	dbf d1,.publish_player_state
	movea.l d7,a1
	moveq #CD_SIZE/2-1,d1
.publish_delay:
	move.w (a0)+,(a1)+
	dbf d1,.publish_delay
	bra .done
.bad:
	moveq #-1,d0
.done:
	adda.w #PS_SIZE+CD_SIZE,sp
	bra .restore
.bad_no_stack:
	moveq #-1,d0
.restore:
	movem.l (sp)+,d1-d7/a0-a6
	rts
