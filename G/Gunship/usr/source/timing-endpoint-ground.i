; Ground resolution for a completed endpoint interval. Not installed.
; Requires endpoint-player, motion-stages and deferred ground definitions.
ER_FREE equ 0
ER_GROUND equ MP_RECORD_SIZE
ER_TERMS equ MP_RECORD_SIZE*2
ER_WORK equ ER_TERMS+MS_TERMS_SIZE

; a0=EP owner, a1=PRIVATE completed endpoint player, a2=prepared stages,
; a3=deferred ground clone, a4=its bound empty event.
; Return 1 contact/reset, 0 airborne, -1 invalid phase/residue/pending event.
; Preserve other registers. No native notification/timer writes.
; Caller owns once-only world scheduling and authoritative publication.
; Commit the deferred event only after publishing player AND owner.
;
; Contact uses committed endpoint height/attitude/vertical speed, with native
; pre-tail forward speed from the interval anchor. On contact, compare native
; free and grounded tails from the same pre-contact record. Replace their XY
; contribution by the difference; snap reset motion to the grounded tail and
; discard its fractional debt. Preserve interval input's other contributions.
endpoint_ground_resolve:
	movem.l d1-d7/a0-a6,-(sp)
	tst.l (a4)
	bne .bad_no_stack
	move.w EP_SPAN(a0),d0
	cmpi.w #1,d0
	beq .span
	cmpi.w #16,d0
	beq .span
	cmpi.w #17,d0
	beq .span
	cmpi.w #20,d0
	bne .bad_no_stack
.span:
	cmp.w EP_DONE(a0),d0
	bne .bad_no_stack
	movea.l a0,a5
	moveq #EM_COUNT-1,d1
.validate:
	cmpi.l #EF_DEN,(a5)+
	bhs .bad_no_stack
	dbf d1,.validate
	tst.w $1c(a1)
	beq .contact
	move.b #1,GD_READY(a4)
	moveq #0,d0
	bra .restore
.contact:
	move.l a0,d2
	move.l a1,d3
	move.l a2,d4
	move.l a3,d5
	move.l a4,d6
	suba.w #ER_WORK,sp
	movea.l sp,a6
	movea.l a6,a3
	moveq #MP_RECORD_SIZE/2-1,d1
.copy:
	move.w (a1)+,(a3)+
	dbf d1,.copy
	; Recover native inputs to the tail, keeping committed pre-contact
	; attitude/height/vertical rate and latest derived target speed.
	lea EP_ANCHOR(a0),a5
	move.l (a5),ER_FREE(a6)
	move.w $2a(a5),ER_FREE+$2a(a6)
	move.b $1b(a5),ER_FREE+$1b(a6)
	movea.l a6,a1
	moveq #MP_RECORD_SIZE/2-1,d1
.duplicate:
	move.w (a1)+,(a3)+
	dbf d1,.duplicate
	lea ER_FREE(a6),a0
	bsr .tail
	movea.l d2,a0
	moveq #0,d0
	tst.w EP_ANCHOR+$1c(a0)
	beq .ground
	moveq #1,d0
.ground:
	lea ER_GROUND(a6),a0
	movea.l d5,a1
	bsr ground_step
	; Zero committed height and a validated Boolean guarantee reset.
	lea ER_GROUND(a6),a0
	bsr .tail
	movea.l d3,a1
	move.w ER_GROUND(a6),d0
	sub.w ER_FREE(a6),d0
	add.w d0,(a1)
	move.w ER_GROUND+2(a6),d0
	sub.w ER_FREE+2(a6),d0
	add.w d0,2(a1)
	; Replacing the tail on a changed-input trajectory can cross a map
	; bound even though both native preview tails were individually clamped.
	; Ground has no wind displacement, so enforce the native bounds here.
	movea.l d2,a0
	bsr .clamp_xy
	addq.l #4,a0
	addq.l #2,a1
	bsr .clamp_xy
	movea.l d3,a1
	; Engine coast uses the new coarse speed at native +09778, so ground
	; can also change RPM even though it does not reset the RPM byte.
	move.b ER_GROUND+$1b(a6),d0
	sub.b ER_FREE+$1b(a6),d0
	add.b d0,$1b(a1)
	move.w ER_GROUND+$2a(a6),$2a(a1)
	move.b ER_GROUND+$50(a6),$50(a1)
	move.b ER_GROUND+$18(a6),$18(a1)
	move.b ER_GROUND+$52(a6),$52(a1)
	clr.b $36(a1)
	clr.b $37(a1)
	clr.b $3e(a1)
	movea.l d2,a0
	clr.l 8(a0)		; height fraction
	clr.l 12(a0)		; forward-speed fraction
	clr.l 28(a0)		; pitch fraction
	clr.l 32(a0)		; roll fraction
	clr.l 36(a0)		; vertical-speed fraction
	movea.l d6,a0
	move.b #1,GD_READY(a0)
	moveq #1,d0
	adda.w #ER_WORK,sp
	bra .restore
.bad_no_stack:
	moveq #-1,d0
.restore:
	movem.l (sp)+,d1-d7/a0-a6
	rts

; a0=nonnegative fractional residue, a1=coordinate word.
.clamp_xy:
	move.w (a1),d0
	cmpi.w #$1800,d0
	blo .xy_low
	cmpi.w #$d800,d0
	blo .xy_done
	move.w #$d800,(a1)
	clr.l (a0)
	rts
.xy_low:
	move.w #$1800,(a1)
	clr.l (a0)
.xy_done:
	rts

; a0=one private record. Raw immutable native stages 3..6 keep the original
; forward response, displacement/clamps/wind and RPM order.
.tail:
	movea.l d4,a1
	lea ER_TERMS(a6),a2
	clr.l (a2)
	clr.l 4(a2)
	clr.l 8(a2)
	moveq #3,d7
.stage:
	move.l d7,d0
	bsr motion_stage
	addq.w #1,d7
	cmpi.w #7,d7
	bne .stage
	rts
