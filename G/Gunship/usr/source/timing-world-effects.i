; Native 0658 effect constructor with explicit deadline inputs.
; Standalone; renderer-side invocation and lifetime migration remain pending.
WE_CODE_SIZE equ $a4

; a0 = validated code hunk, a1 = even WE_CODE_SIZE code buffer,
; a2 = prepared deadline RNG base, a3 = stable private heading word address.
; Native constructor ABI is retained, including a5 pose and register clobbers.
; Original allocator, tables and sine helper remain authoritative.
; Return d0=0/-1, preserve other registers. Validate before destination writes.
; Caller owns non-overlap/lifetimes and MUST flush instruction caches.
world_effect_prepare:
	movem.l d1-d2/a0-a5,-(sp)
	movea.l a0,a4
	adda.l #$9b9a,a4
	cmpi.w #$4eb9,(a4)
	bne .bad
	movea.l a0,a5
	adda.l #$bea8,a5
	cmpa.l 2(a4),a5
	bne .bad
	cmpi.l #$6700009a,6(a4)
	bne .bad
	cmpi.w #$3039,$30(a4)
	bne .bad
	cmpi.w #$4e75,$a2(a4)
	bne .bad
	lea $7a6a(a0),a5
	lea .rng_sites(pc),a0
	moveq #2,d2
.validate:
	move.w (a0)+,d1
	cmpi.w #$4eb9,0(a4,d1.w)
	bne .bad
	cmpa.l 2(a4,d1.w),a5
	bne .bad
	dbf d2,.validate
	movea.l a1,a5
	moveq #WE_CODE_SIZE/2-1,d2
.copy:
	move.w (a4)+,(a5)+
	dbf d2,.copy
	move.l a3,$32(a1)
	lea WR_REGISTER_ENTRY(a2),a5
	lea .rng_sites(pc),a0
	moveq #2,d2
.patch:
	move.w (a0)+,d1
	move.l a5,2(a1,d1.w)
	dbf d2,.patch
	moveq #0,d0
	bra .done
.bad:
	moveq #-1,d0
.done:
	movem.l (sp)+,d1-d2/a0-a5
	rts
.rng_sites:
	dc.w $6a,$80,$90
