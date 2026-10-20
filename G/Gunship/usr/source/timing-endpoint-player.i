; Transactional endpoint-preserving airborne player owner. Not installed.
; Requires player-step, control-delay, endpoint-motion and endpoint-impulse.
EP_FRACTIONS equ 0
EP_DELAY equ EM_SIZE
EP_ANCHOR equ EP_DELAY+CD_SIZE
EP_SPAN equ EP_ANCHOR+MP_RECORD_SIZE
EP_DONE equ EP_SPAN+2
EP_TICK equ EP_DONE+2
EP_SIZE equ EP_TICK+2
EP_WORK_PS equ EP_SIZE
EP_WORK_CANDIDATE equ EP_WORK_PS+PS_SIZE
EP_WORK_OUTPUT equ EP_WORK_CANDIDATE+MP_RECORD_SIZE
EP_WORK_BASE equ EP_WORK_OUTPUT+MP_RECORD_SIZE
EP_WORK_SOURCE equ EP_WORK_BASE+MP_RECORD_SIZE
EP_WORK_PACKET equ EP_WORK_SOURCE+MP_RECORD_SIZE
EP_WORK_PREVIOUS equ EP_WORK_PACKET+PS_INPUT_SIZE
EP_WORK_IMPULSE equ EP_WORK_PREVIOUS+2
EP_WORK_SIZE equ EP_WORK_IMPULSE+2

; a0=EP_SIZE state, d0=rate 3/50/60, d1=previous Y -1..1.
; Return 0/-1; other registers preserved. Invalid input changes nothing.
endpoint_player_init:
	movem.l d1-d2/a0-a1,-(sp)
	movea.l a0,a1
	lea EP_DELAY(a0),a0
	bsr control_delay_init
	tst.l d0
	bne .done
	movea.l a1,a0
	moveq #EM_COUNT-1,d2
.fractions:
	clr.l (a0)+
	dbf d2,.fractions
	lea EP_ANCHOR(a1),a0
	moveq #(EP_SIZE-EP_ANCHOR)/2-1,d2
.rest:
	clr.w (a0)+
	dbf d2,.rest
.done:
	movem.l (sp)+,d1-d2/a0-a1
	rts

; Start only after the preceding interval completed and world effects were
; committed. a0=state, a1=player, d0=delivered span, d1=logical tick 0..65535.
; Retains fractions/history; captures the new continuous anchor. Scheduler
; owns PAL 17/17/16 selection and lifecycle rebasing through init.
endpoint_player_begin:
	movem.l d2/a0-a2,-(sp)
	cmpi.l #65535,d1
	bhi .bad
	move.w EP_DONE(a0),d2
	cmp.w EP_SPAN(a0),d2
	bne .bad
	cmpi.w #50,EP_DELAY+CD_RATE(a0)
	bne .ntsc
	cmpi.l #16,d0
	beq .valid
	cmpi.l #17,d0
	beq .valid
	bra .bad
.ntsc:
	cmpi.w #60,EP_DELAY+CD_RATE(a0)
	bne .whole
	cmpi.l #20,d0
	beq .valid
	bra .bad
.whole:
	cmpi.w #3,EP_DELAY+CD_RATE(a0)
	bne .bad
	cmpi.l #1,d0
	bne .bad
.valid:
	move.w d0,EP_SPAN(a0)
	clr.w EP_DONE(a0)
	move.w d1,EP_TICK(a0)
	lea EP_ANCHOR(a0),a2
	moveq #MP_RECORD_SIZE/2-1,d2
.copy:
	move.w (a1)+,(a2)+
	dbf d2,.copy
	moveq #0,d0
	bra .done
.bad:
	moveq #-1,d0
.done:
	movem.l (sp)+,d2/a0-a2
	rts

; a0=state, a1=player, a2=prepared stages, a3=sine helper, a4=packet,
; d0=consecutive field stamp. Return 0/-1, preserving other registers.
; Private preview overlays anchored motion onto CURRENT non-motion inputs,
; so field-stamped commands can change the contribution immediately.
; Publishes ten motion fields plus derived target speed/power/lift/RPM target/
; coarse speed. Publishes the preview's consumed yaw only on the interval's
; final field, which the scheduler bridge binds to the world deadline.
; No RNG, ground effects or world acknowledgement.
; Nonzero packet impulses are accepted only on the final field. Matching
; native previews apply their full difference after ordinary field motion.
; The world owner generates/retains the packet once; this code never draws RNG.
; No step after the interval ends, and failed preview cannot consume history.
; Caller supplies validated code and distinct buffers, serialized foreground.
endpoint_player_step:
	movem.l d1-d7/a0-a6,-(sp)
	move.l a0,d2
	move.l a1,d3
	move.l a2,d4
	move.l a3,d5
	move.l a4,d6
	move.l d0,d7
	suba.w #EP_WORK_SIZE,sp
	movea.l sp,a6
	move.w 4(a4),d1
	or.w 6(a4),d1
	or.w 8(a4),d1
	move.w d1,EP_WORK_IMPULSE(a6)
	beq .no_impulse
	move.w EP_DONE(a0),d1
	addq.w #1,d1
	cmp.w EP_SPAN(a0),d1
	bne .bad
.no_impulse:
	lea EP_WORK_PACKET(a6),a2
	move.l (a4),(a2)
	clr.l 4(a2)
	clr.w 8(a2)
	movea.l a6,a2
	moveq #EP_SIZE/2-1,d1
.state:
	move.w (a0)+,(a2)+
	dbf d1,.state
	move.w EP_DONE(a6),d0
	cmp.w EP_SPAN(a6),d0
	bhs .bad
	lea EP_WORK_CANDIDATE(a6),a0
	lea EP_WORK_OUTPUT(a6),a2
	moveq #MP_RECORD_SIZE/2-1,d1
.player:
	move.w (a1),(a0)+
	move.w (a1)+,(a2)+
	dbf d1,.player
	lea EP_ANCHOR(a6),a0
	lea EP_WORK_CANDIDATE(a6),a1
	lea endpoint_motion_fields(pc),a2
	moveq #EM_COUNT-1,d1
.anchor:
	move.w (a2)+,d0
	btst #0,1(a2)
	beq .byte
	move.w (a0,d0.w),(a1,d0.w)
	bra .next
.byte:
	move.b (a0,d0.w),(a1,d0.w)
.next:
	addq.l #2,a2
	dbf d1,.anchor
	; Native +0939c reads the PREVIOUS coarse speed before +09674
	; replaces it. It belongs to the flight anchor, despite being derived.
	; Feeding the last field preview back here changes configuration-2 power.
	move.b $50(a0),$50(a1)
	tst.w EP_WORK_IMPULSE(a6)
	beq .source_saved
	lea EP_WORK_SOURCE(a6),a2
	moveq #MP_RECORD_SIZE/2-1,d1
.source:
	move.w (a1)+,(a2)+
	dbf d1,.source
.source_saved:
	lea EP_DELAY(a6),a0
	movea.l d6,a1
	move.w 2(a1),d1
	ext.l d1
	move.l d7,d0
	bsr control_delay_step
	tst.l d1
	bne .bad
	move.w d0,EP_WORK_PREVIOUS(a6)
	move.l d0,d1
	moveq #3,d0
	lea EP_WORK_PS(a6),a0
	bsr player_step_init
	tst.l d0
	bne .bad
	lea EP_WORK_CANDIDATE(a6),a1
	movea.l d4,a2
	movea.l d5,a3
	lea EP_WORK_PACKET(a6),a4
	moveq #0,d0
	move.w EP_TICK(a6),d0
	bsr player_step_interval
	tst.l d0
	bne .bad
	movea.l a6,a0
	lea EP_ANCHOR(a6),a1
	lea EP_WORK_CANDIDATE(a6),a2
	lea EP_WORK_OUTPUT(a6),a3
	moveq #0,d0
	move.w EP_SPAN(a6),d0
	bsr endpoint_motion_step
	tst.l d0
	bne .bad
	move.w $30(a2),$30(a3)
	move.b $38(a2),$38(a3)
	move.b $3a(a2),$3a(a3)
	move.b $40(a2),$40(a3)
	move.b $50(a2),$50(a3)
	addq.w #1,EP_DONE(a6)
	move.w EP_DONE(a6),d0
	cmp.w EP_SPAN(a6),d0
	bne .retain_yaw
	; Use the native preview's branch decision, not a new predicate on
	; interpolated pitch/height. Commands remain responsive during the tick.
	move.b $3f(a2),$3f(a3)
.retain_yaw:
	tst.w EP_WORK_IMPULSE(a6)
	beq .publish
	lea EP_WORK_CANDIDATE(a6),a0
	lea EP_WORK_BASE(a6),a1
	lea EP_WORK_SOURCE(a6),a2
	moveq #MP_RECORD_SIZE/2-1,d1
.second_candidate:
	move.w (a0),(a1)+
	move.w (a2)+,(a0)+
	dbf d1,.second_candidate
	lea EP_WORK_PS(a6),a0
	moveq #3,d0
	move.w EP_WORK_PREVIOUS(a6),d1
	ext.l d1
	bsr player_step_init
	tst.l d0
	bne .bad
	lea EP_WORK_CANDIDATE(a6),a1
	movea.l d4,a2
	movea.l d5,a3
	movea.l d6,a4
	moveq #0,d0
	move.w EP_TICK(a6),d0
	bsr player_step_interval
	tst.l d0
	bne .bad
	movea.l a6,a0
	lea EP_WORK_OUTPUT(a6),a1
	lea EP_WORK_BASE(a6),a2
	lea EP_WORK_CANDIDATE(a6),a3
	bsr endpoint_impulse_apply
	tst.l d0
	bne .bad
.publish:
	lea EP_WORK_OUTPUT(a6),a3
	movea.l a6,a0
	movea.l d2,a1
	moveq #EP_SIZE/2-1,d1
.publish_state:
	move.w (a0)+,(a1)+
	dbf d1,.publish_state
	movea.l d3,a1
	moveq #MP_RECORD_SIZE/2-1,d1
.publish_player:
	move.w (a3)+,(a1)+
	dbf d1,.publish_player
	moveq #0,d0
	bra .done
.bad:
	moveq #-1,d0
.done:
	adda.w #EP_WORK_SIZE,sp
	movem.l (sp)+,d1-d7/a0-a6
	rts
