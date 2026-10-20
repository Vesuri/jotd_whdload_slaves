; World-owned motion RNG. Standalone; not installed in the native loop.
; a0=authoritative player, a1=10-byte player-step packet,
; a2=validated native RNG entry (+07a5c). Return d0=0; others preserved.
; Writes only packet impulse words and the native RNG's own state.
; Does not apply impulses or mutate the player. Call ONCE per world tick,
; after native clock/input setup, before applying that boundary's motion.
; Eligibility fields are unchanged by attitude and stage-0 arithmetic.
; Caller owns RNG mode/input-event timestamp and serialization with all other RNG users.
world_motion_impulses:
	movem.l d1-d7/a0-a6,-(sp)
	movea.l a0,a5
	movea.l a1,a4
	movea.l a2,a6
	clr.l 4(a4)
	clr.w 8(a4)
	btst #0,$0f(a5)
	beq .pitch
	jsr (a6)
	mulu.w #$300,d0
	swap d0
	subq.w #1,d0
	lsl.w #2,d0
	move.w d0,4(a4)
.pitch:
	tst.b $1c(a5)
	bne .heading
	cmpi.w #8,$2a(a5)
	blo .heading
	move.b $1d(a5),d0
	cmp.b $2b(a5),d0
	bhs .heading
	jsr (a6)
	mulu.w #$300,d0
	swap d0
	subq.w #1,d0
	move.w d0,6(a4)
.heading:
	tst.w $1c(a5)
	beq .done
	move.w $0e(a5),d0
	andi.w #3,d0
	beq .done
	jsr (a6)
	mulu.w #$500,d0
	swap d0
	subq.b #2,d0
	ext.w d0
	move.w d0,8(a4)
.done:
	moveq #0,d0
	movem.l (sp)+,d1-d7/a0-a6
	rts
