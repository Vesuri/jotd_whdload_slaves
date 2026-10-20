; Native scripted-object world work, split before its blocking modal interpreter.
; Standalone; requires world-rng and world-damage (WH_ENTRY).
SC_PREFIX_SIZE equ $36       ; +09f74..+09faa
SC_BODY equ SC_PREFIX_SIZE+2 ; appended RTS before +09fb0 body
SC_BODY_SIZE equ $19c        ; +09fb0..+0a14c, includes RTS
SC_PLAYER equ SC_BODY+SC_BODY_SIZE
SC_SIZE equ SC_PLAYER+4

; a0=hunk 0, a1=even clone, a2=deadline RNG, a3=hit clone base, a4=hunk 6.
; Return 0/-1; preserve others. Validate changed/removed boundaries first.
; Caller owns nonoverlap, version validation and instruction-cache flushing.
world_script_prepare:
	movem.l d1/a0/a5-a6,-(sp)
	movea.l a0,a6
	adda.l #$9f74,a0
	cmpi.l #$302d0000,(a0)
	bne .bad
	cmpi.l #$1b42002c,$32(a0)
	bne .bad
	cmpi.w #$4eb9,$36(a0)
	bne .bad
	movea.l a6,a5
	adda.l #$8050,a5
	cmpa.l $38(a0),a5
	bne .bad
	cmpi.l #$4a2d0053,(a5)
	bne .bad
	cmpi.l #$6f00014e,4(a5)
	bne .bad
	cmpi.l #$532d0054,8(a5)
	bne .bad
	cmpi.l #$66000146,$c(a5)
	bne .bad
	cmpi.w #$7005,$3c(a0)
	bne .bad
	cmpi.w #$4eb9,$176(a0)
	bne .bad
	lea $7a5c(a6),a5
	cmpa.l $178(a0),a5
	bne .bad
	cmpi.w #$4eb9,$18a(a0)
	bne .bad
	lea $7d92(a6),a5
	cmpa.l $18c(a0),a5
	bne .bad
	cmpi.w #$4e75,$1d6(a0)
	bne .bad
	movea.l a1,a5
	moveq #SC_PREFIX_SIZE/2-1,d1
.prefix:
	move.w (a0)+,(a5)+
	dbf d1,.prefix
	move.w #$4e75,(a5)+
	addq.l #6,a0              ; omit native modal-interpreter call
	move.w #SC_BODY_SIZE/2-1,d1
.body:
	move.w (a0)+,(a5)+
	dbf d1,.body
	lea $3b88(a4),a5
	move.l a5,SC_PLAYER(a1)
	move.l a2,SC_BODY+$13c(a1)
	lea WH_ENTRY(a3),a5
	move.l a5,SC_BODY+$150(a1)
	moveq #0,d0
	bra .done
.bad:
	moveq #-1,d0
.done:
	movem.l (sp)+,d1/a0/a5-a6
	rts

; a0=native player, a1=clone. Return 0 completed, 2 modal/lifecycle boundary,
; -1 wrong binding. Preserve other registers. Prefix may have armed a script
; when returning 2, but countdown remains 1 for the native lifecycle handler.
; Do not retry the whole step or acknowledge this world tick on return 2.
world_script_step:
	movem.l d1-d7/a0-a6,-(sp)
	cmpa.l SC_PLAYER(a1),a0
	bne .bad
	movea.l a0,a5
	movem.l a0-a1,-(sp)
	jsr (a1)
	movem.l (sp)+,a0-a1
	tst.b $53(a5)
	ble .body
	cmpi.b #1,$54(a5)
	beq .boundary
	subq.b #1,$54(a5)         ; preserve native zero-to-FF countdown wrap
.body:
	lea SC_BODY(a1),a1
	jsr (a1)
	moveq #0,d0
	bra .done
.boundary:
	moveq #2,d0
	bra .done
.bad:
	moveq #-1,d0
.done:
	movem.l (sp)+,d1-d7/a0-a6
	rts

; Explicit continuation ONLY after lifecycle owner completed native +08050.
; Run remaining object work without re-running prefix or decrementing timer.
world_script_resume:
	movem.l d1-d7/a0-a6,-(sp)
	cmpa.l SC_PLAYER(a1),a0
	bne .bad
	movea.l a0,a5
	lea SC_BODY(a1),a1
	jsr (a1)
	moveq #0,d0
	bra .done
.bad:
	moveq #-1,d0
.done:
	movem.l (sp)+,d1-d7/a0-a6
	rts
