; Standalone field-owned command targets, not installed in gameplay yet.
; a0 = native player record, d0.w = complete accepted key/modifier word.
; Returns d0=1 for an owned primary effect, 0 otherwise.
; Preserves d1-d7/a0-a6; CCR unspecified. Does NOT run the common tail.
; Full-word comparisons preserve the native modifier semantics.

control_target_command:
	movem.l d1-d2,-(sp)
	move.w d0,d2
	cmpi.w #$4c,d2
	beq .front
	cmpi.w #$4d,d2
	beq .front
	cmpi.w #$4e,d2
	beq .right
	cmpi.w #$4f,d2
	beq .left
	cmpi.w #$50,d2
	beq .up4
	cmpi.w #$5a,d2
	beq .up4
	cmpi.w #$51,d2
	beq .up1
	cmpi.w #$5b,d2
	beq .up1
	cmpi.w #$52,d2
	beq .down1
	cmpi.w #$5c,d2
	beq .down1
	cmpi.w #$53,d2
	beq .down4
	cmpi.w #$5d,d2
	beq .down4
	cmpi.w #$38,d2
	beq .yawleft
	cmpi.w #$39,d2
	beq .yawzero
	cmpi.w #$3a,d2
	beq .yawright
	moveq #0,d0
	bra .done
.front:
	clr.b $1a(a0)
	bra .handled
.right:
	move.b #32,$1a(a0)
	bra .handled
.left:
	move.b #-32,$1a(a0)
	bra .handled
.up4:
	move.b $39(a0),d1
	addq.b #4,d1
	bra .collective
.up1:
	move.b $39(a0),d1
	addq.b #1,d1
	bra .collective
.down1:
	move.b $39(a0),d1
	subq.b #1,d1
	bra .collective
.down4:
	move.b $39(a0),d1
	subq.b #4,d1
.collective:
	bmi .zero
	cmpi.b #43,d1
	bcs .store
	moveq #42,d1
	bra .store
.zero:
	moveq #0,d1
.store:
	move.b d1,$39(a0)
	bra .handled
.yawleft:
	subq.b #1,$3f(a0)
	bra .handled
.yawzero:
	clr.b $3f(a0)
	bra .handled
.yawright:
	addq.b #1,$3f(a0)
.handled:
	moveq #1,d0
.done:
	movem.l (sp)+,d1-d2
	rts

; Native +052cc..+052f8, factored from primary command ownership.
; Run once per ordinary continuing command, including unknown keys.
; Exceptional/modal commands require their native exit ordering instead.
; a0 = player record. Preserves all data/address registers; CCR unspecified.
control_target_tail:
	move.l d0,-(sp)
	move.b $3f(a0),d0
	bmi .negative
	cmpi.b #4,d0
	bls .speed
	moveq #4,d0
	bra .clamp
.negative:
	cmpi.b #-4,d0
	bhi .speed
	moveq #-4,d0
.clamp:
	move.b d0,$3f(a0)
.speed:
	move.b $50(a0),d0
	bmi .compare
	neg.b d0
.compare:
	cmpi.b #15,d0
	bcs .done
	clr.b $3f(a0)
.done:
	move.l (sp)+,d0
	rts
