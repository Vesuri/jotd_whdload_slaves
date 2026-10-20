; Native guided-weapon field state; optional retained sprite request binding.
; Replay in delivered-field order; do not also run the native VBL state owner.
FG_CODE_SIZE equ $128        ; +0a1c8..+0a2f0, includes native RTS exits
FG_QUIT equ FG_CODE_SIZE
FG_ENABLED equ FG_QUIT+4
FG_PENDING equ FG_ENABLED+4
FG_PRESENT equ FG_PENDING+4 ; optional retained sprite presentation context
FG_EFFECTS equ FG_PRESENT+4 ; native shared effect slot table
FG_SIZE equ FG_EFFECTS+4

; a0=validated 0658 hunk 0, a1=even clone, a2=validated hunk 4,
; a3=private pending-display byte (initialized by lifecycle owner).
; Return 0/-1, preserve others. Validate callback boundaries before writing.
; Only the pending byte is private; caller owns buffers and cache flushing.
field_guidance_prepare:
	movem.l d1-d2/a0-a6,-(sp)
	movea.l a3,a6
	movea.l a0,a3
	adda.l #$a1c8,a3
	cmpi.l #$42421439,(a3)
	bne .bad
	movea.l a0,a5
	adda.l #$a44d,a5
	cmpa.l 4(a3),a5
	bne .bad
	cmpi.w #$4e75,FG_CODE_SIZE-2(a3)
	bne .bad
	lea .pending(pc),a4
	moveq #3,d2
.pending_check:
	move.w (a4)+,d1
	move.w (a4)+,d0
	cmp.w -2(a3,d1.w),d0
	bne .bad
	movea.l a0,a5
	adda.l #$c757,a5
	cmpa.l 0(a3,d1.w),a5
	bne .bad
	dbf d2,.pending_check
	lea .calls(pc),a4
	moveq #3,d2
.validate:
	move.w (a4)+,d1
	cmpi.w #$4eb9,0(a3,d1.w)
	bne .bad
	moveq #0,d0
	move.w (a4)+,d0
	; a0 was saved and remains the code-hunk base.
	movea.l a0,a5
	adda.l d0,a5
	cmpa.l 2(a3,d1.w),a5
	bne .bad
	dbf d2,.validate
	movea.l a1,a5
	move.w #FG_CODE_SIZE/2-1,d2
.copy:
	move.w (a3)+,(a5)+
	dbf d2,.copy
	lea $1c6(a2),a5
	move.l a5,FG_QUIT(a1)
	movea.l a0,a5
	adda.l #$a44e,a5
	move.l a5,FG_ENABLED(a1)
	move.l a6,FG_PENDING(a1)
	clr.l FG_PRESENT(a1)
	movea.l a0,a5
	adda.l #$c6d0,a5
	move.l a5,FG_EFFECTS(a1)
	lea .pending(pc),a4
	moveq #3,d2
.pending_patch:
	move.w (a4)+,d1
	addq.l #2,a4
	move.l a6,0(a1,d1.w)
	dbf d2,.pending_patch
	lea .calls(pc),a4
	moveq #3,d2
.patch:
	move.w (a4)+,d1
	addq.l #2,a4
	move.l #$4e714e71,0(a1,d1.w)
	move.w #$4e71,4(a1,d1.w)
	dbf d2,.patch
	moveq #0,d0
	bra .done
.bad:
	moveq #-1,d0
.done:
	movem.l (sp)+,d1-d2/a0-a6
	rts
.calls:
	dc.w $44,$a35a,$c2,$a2f0,$f6,$a2f0,$114,$a2f0
.pending:
	dc.w $24,$50f9,$2a,$4a39,$4e,$50f9,$5c,$4a39

; Hybrid entry: acknowledge the previous field's display request independently
; of actual screen swaps, then evaluate native state. This retains the earliest
; native one-field handshake. No acknowledgement while inactive.
field_guidance_advance:
	movem.l a1,-(sp)
	movea.l FG_QUIT(a0),a1
	tst.b (a1)
	bne .inactive
	movea.l FG_ENABLED(a0),a1
	tst.b (a1)
	beq .inactive
	movea.l FG_PENDING(a0),a1
	clr.b (a1)
	movem.l (sp)+,a1
	bra field_guidance_step
.inactive:
	moveq #0,d0
	movem.l (sp)+,a1
	rts

; a0=prepared clone. Native-equivalence entry: pending byte is caller supplied.
; Native VBL gate: quit byte zero, enabled byte nonzero.
; Return 1 state evaluated, 0 inactive; preserve other registers.
; Once per delivered field, with constructors and world work serialized in
; chronological order. Native VBL installation must exclude this state owner.
; Display work must be rebuilt separately; this does not draw or acknowledge.
field_guidance_step:
	movem.l d1-d7/a0-a6,-(sp)
	movea.l FG_QUIT(a0),a1
	tst.b (a1)
	bne .inactive
	movea.l FG_ENABLED(a0),a1
	tst.b (a1)
	beq .inactive
	jsr (a0)
	moveq #1,d0
	bra .done
.inactive:
	moveq #0,d0
.done:
	movem.l (sp)+,d1-d7/a0-a6
	rts
