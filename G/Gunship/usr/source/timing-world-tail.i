; Native periodic completion and flight-end cleanup. Not installed.
; Requires world-reserves and world-periodic. Caller invokes once per world tick.
WT_CLEANUP_SIZE equ $46       ; +058c6..+0590c, includes RTS

; a0=validated hunk 0, a1=even cleanup clone, a2=validated hunk 4.
; Return 0/-1, preserve others; no writes on signature failure.
; Nonoverlapping buffers and instruction-cache flush required.
world_cleanup_prepare:
	movem.l d1-d2/a0-a5,-(sp)
	lea $58c6(a0),a4
	cmpi.w #$7005,(a4)
	bne .bad
	cmpi.l #$727941ed,$14(a4)
	bne .bad
	cmpi.l #$0c410005,$32(a4)
	bne .bad
	cmpi.w #$4279,$38(a4)
	bne .bad
	movea.l a0,a5
	adda.l #$ba08,a5
	cmpa.l $3a(a4),a5
	bne .bad
	cmpi.w #$50f9,$3e(a4)
	bne .bad
	lea $1c6(a2),a5
	cmpa.l $40(a4),a5
	bne .bad
	cmpi.w #$4e75,$44(a4)
	bne .bad
	lea .calls(pc),a3
	moveq #2,d2
.validate:
	move.w (a3)+,d1
	cmpi.w #$4eb9,0(a4,d1.w)
	bne .bad
	moveq #0,d0
	move.w (a3)+,d0
	movea.l a0,a5
	adda.l d0,a5
	cmpa.l 2(a4,d1.w),a5
	bne .bad
	dbf d2,.validate
	movea.l a1,a5
	moveq #WT_CLEANUP_SIZE/2-1,d1
.copy:
	move.w (a4)+,(a5)+
	dbf d1,.copy
	moveq #0,d0
	bra .done
.bad:
	moveq #-1,d0
.done:
	movem.l (sp)+,d1-d2/a0-a5
	rts
.calls:
	dc.w $02,$7b7e,$0e,$7bd0,$28,$b726

; a0=native authoritative player, a1=reserves clone, a2=periodic clone,
; a3=cleanup clone. Return 0 nonperiodic, 1 periodic completed, 2 flight ended,
; or -1 bad player binding (no writes). Preserve all non-result registers.
; Never advance tick here: opening/motion/weapons/damage/scripts must precede it.
; On return 2, the lifecycle owner must stop sampling/rebase before another field.
world_tail_step:
	movem.l d1-d7/a0-a6,-(sp)
	cmpa.l WP_CODE_SIZE(a2),a0
	bne .bad
	bsr world_reserves_step
	tst.l d0
	beq .done
	cmpi.l #2,d0
	beq .cleanup
	movea.l a2,a1
	bsr world_periodic_step
	tst.l d0
	bmi .done
	moveq #1,d0
	bra .done
.cleanup:
	movea.l a0,a5
	jsr (a3)
	moveq #2,d0
	bra .done
.bad:
	moveq #-1,d0
.done:
	movem.l (sp)+,d1-d7/a0-a6
	rts
