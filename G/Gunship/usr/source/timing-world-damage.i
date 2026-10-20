; Native damage scan and nested hit routine with deadline-owned RNG/effects.
; Standalone; requires world-rng and a prepared world-effect constructor.
WH_ENTRY equ 8               ; keep preceding PC-relative lookup table
WH_CODE_SIZE equ $13e        ; +07d8a..+07ec8
WD_CODE_SIZE equ $316        ; +09c5c..+09f72
WD_SIZE equ WD_CODE_SIZE+4

; a0=hunk 0, a1=even hit clone, a2=deadline RNG. Native ABI at clone+WH_ENTRY:
; a5=authoritative player, d0=notification code; native register clobbers retained.
; Return 0/-1, preserve others. Caller owns buffers and instruction-cache flush.
world_hit_prepare:
	movem.l d1/a0/a3-a4,-(sp)
	lea $7d8a(a0),a3
	cmpi.l #$0408ff08,(a3)
	bne .bad
	cmpi.l #$ffffffff,4(a3)
	bne .bad
	cmpi.l #$b03b10da,$24(a3)
	bne .bad
	cmpi.w #$4eb9,8(a3)
	bne .bad
	movea.l a0,a4
	adda.l #$a150,a4
	cmpa.l $a(a3),a4
	bne .bad
	lea $7a5c(a0),a4
	cmpi.w #$4eb9,$e(a3)
	bne .bad
	cmpa.l $10(a3),a4
	bne .bad
	cmpi.w #$4eb9,$3c(a3)
	bne .bad
	cmpa.l $3e(a3),a4
	bne .bad
	cmpi.w #$4e75,WH_CODE_SIZE-2(a3)
	bne .bad
	movea.l a1,a4
	move.w #WH_CODE_SIZE/2-1,d1
.copy:
	move.w (a3)+,(a4)+
	dbf d1,.copy
	move.l a2,$10(a1)
	move.l a2,$3e(a1)
	moveq #0,d0
	bra .done
.bad:
	moveq #-1,d0
.done:
	movem.l (sp)+,d1/a0/a3-a4
	rts

; a0=hunk 0, a1=even damage clone, a2=deadline RNG, a3=world effect clone,
; a4=hit clone base, a5=hunk 6. Return 0/-1, preserve others.
; Validate before writes. All callbacks except these private-input routes stay
; native. Effects consume the caller's committed world heading, not render state.
world_damage_prepare:
	movem.l d1-d2/a0-a6,-(sp)
	movea.l a0,a6
	adda.l #$9c5c,a6
	cmpi.l #$102d0017,(a6)
	bne .bad
	cmpi.w #$4e75,WD_CODE_SIZE-2(a6)
	bne .bad
	; Validate each changed call against its native destination.
	move.l a3,-(sp)
	lea .calls(pc),a3
	moveq #3,d2
.validate:
	move.w (a3)+,d1
	cmpi.w #$4eb9,0(a6,d1.w)
	bne .bad_pop
	moveq #0,d0
	move.w (a3)+,d0
	add.l a0,d0
	cmp.l 2(a6,d1.w),d0
	bne .bad_pop
	dbf d2,.validate
	movea.l (sp)+,a3
	movea.l a1,a0
	move.w #WD_CODE_SIZE/2-1,d1
.copy:
	move.w (a6)+,(a0)+
	dbf d1,.copy
	lea $3b88(a5),a0
	move.l a0,WD_CODE_SIZE(a1)
	move.l a3,$1d0(a1)
	move.l a2,$1d6(a1)
	lea WH_ENTRY(a4),a0
	move.l a0,$1e8(a1)
	move.l a3,$1fc(a1)
	moveq #0,d0
	bra .done
.bad_pop:
	movea.l (sp)+,a3
.bad:
	moveq #-1,d0
.done:
	movem.l (sp)+,d1-d2/a0-a6
	rts
.calls:
	dc.w $1ce,$9b9a,$1d4,$7a5c,$1e6,$7d92,$1fa,$9b9a

; a0=bound native player with tables, a1=damage clone. Return 0/-1.
; Run once after native world weapons/actors, before scripts/periodic tail.
; Authoritative damage, allocation, counters and UI effects are not rolled back.
world_damage_step:
	movem.l d1-d7/a0-a6,-(sp)
	cmpa.l WD_CODE_SIZE(a1),a0
	bne .bad
	movea.l a0,a5
	jsr (a1)
	moveq #0,d0
	bra .done
.bad:
	moveq #-1,d0
.done:
	movem.l (sp)+,d1-d7/a0-a6
	rts
