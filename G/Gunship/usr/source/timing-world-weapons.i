; Native 0658 weapons/actors with private deadline fire flags and RNG.
; Standalone. Requires timing-world-rng.i; native callbacks remain authoritative.
WW_CODE_SIZE equ $3fe          ; +0979c..+09b9a, includes RTS
WW_SIZE equ WW_CODE_SIZE+4     ; native player binding after code

; a0=hunk 0, a1=even clone, a2=deadline RNG, a3=private two-byte fire packet,
; a4=hunk 6. Return 0/-1; preserve non-result registers. Validate before writes.
; Caller validates version, owns nonoverlapping lifetimes and flushes caches.
world_weapons_prepare:
	movem.l d1-d3/a0-a6,-(sp)
	movea.l a0,a6
	adda.l #$979c,a0
	cmpi.w #$4239,(a0)
	bne .bad
	movea.l a6,a5
	adda.l #$b92c,a5
	cmpa.l 2(a0),a5
	bne .bad
	cmpi.w #$4eb9,$1a(a0)
	bne .bad
	movea.l a6,a5
	adda.l #$bed4,a5
	cmpa.l $1c(a0),a5
	bne .bad
	cmpi.w #$4eb9,$25e(a0)
	bne .bad
	lea $7a5c(a6),a5
	cmpa.l $260(a0),a5
	bne .bad
	cmpi.w #$4e75,WW_CODE_SIZE-2(a0)
	bne .bad
	lea .fire(pc),a6
	moveq #7,d3
.validate:
	move.w (a6)+,d1
	move.w (a6)+,d2
	cmp.w -2(a0,d1.w),d2
	bne .bad
	moveq #0,d2
	move.w (a6)+,d2
	lea $4292(a4),a5
	adda.l d2,a5
	cmpa.l 0(a0,d1.w),a5
	bne .bad
	dbf d3,.validate
	movea.l a1,a5
	move.w #WW_CODE_SIZE/2-1,d3
.copy:
	move.w (a0)+,(a5)+
	dbf d3,.copy
	lea $3b88(a4),a5
	move.l a5,WW_CODE_SIZE(a1)
	move.l a2,$260(a1)          ; native default bound 256 entry
	lea .fire(pc),a6
	moveq #7,d3
.patch:
	move.w (a6)+,d1
	addq.l #2,a6
	moveq #0,d2
	move.w (a6)+,d2
	movea.l a3,a5
	adda.l d2,a5
	move.l a5,0(a1,d1.w)
	dbf d3,.patch
	moveq #0,d0
	bra .done
.bad:
	moveq #-1,d0
.done:
	movem.l (sp)+,d1-d3/a0-a6
	rts
.fire:
	; operand offset, native opcode, byte offset within the two-byte packet
	dc.w $016,$4239,0,$05e,$4a79,0,$096,$4279,0,$1be,$4a39,0
	dc.w $2f6,$4239,0,$3de,$4239,0,$0a0,$4a39,1,$0b8,$4239,1

; a0=native authoritative player with trailing object tables, a1=prepared clone.
; Return 0/-1, preserve others. Authoritative effects are real, not a preview.
; Run once per world tick after committed player motion and command dispatch.
world_weapons_step:
	movem.l d1-d7/a0-a6,-(sp)
	cmpa.l WW_CODE_SIZE(a1),a0
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
