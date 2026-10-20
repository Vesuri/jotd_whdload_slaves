; Native 0658 RNG bound to a private deadline record. Standalone, not installed.
; Keep native seed, replay-mode byte, authoritative tick and arithmetic.
; Only timestamp reads are redirected; live input memory is never replaced.
WR_CODE_SIZE equ $6c
WR_BOUNDED_ENTRY equ $0a        ; bound.l at 4(sp)
WR_REGISTER_ENTRY equ $0e       ; bound in low word of d1

; a0 = validated native RNG (+07a5c), a1 = even WR_CODE_SIZE code buffer,
; a2 = stable private TH_RECORD_SIZE field record, a3 = native input hunk.
; d0 = 0 success, -1 unexpected patch boundary/input source.
; Preserve other registers. Caller owns non-overlap, lifetime and version
; validation, and MUST flush instruction caches before executing the clone.
; Prepare once for a fixed private record address; update that record only
; between world updates. Calls through all three entries retain the native ABI.
; Native world users must all be routed here in their original order.
; Do not use this entry for renderer-only effects or speculative motion.
world_rng_prepare:
	movem.l d1/a0-a4,-(sp)
	cmpi.l #$223c0000,(a0)
	bne .bad
	cmpi.l #$01006000,4(a0)
	bne .bad
	cmpi.l #$0006222f,8(a0)
	bne .bad
	cmpi.w #$0004,$0c(a0)
	bne .bad
	cmpi.w #$2439,$20(a0)
	bne .bad
	lea $18(a3),a4
	cmpa.l $22(a0),a4
	bne .bad
	cmpi.w #$2439,$32(a0)
	bne .bad
	lea $14(a3),a4
	cmpa.l $34(a0),a4
	bne .bad
	cmpi.w #$4e75,$6a(a0)
	bne .bad
	movea.l a1,a4
	moveq #WR_CODE_SIZE/2-1,d1
.copy:
	move.w (a0)+,(a4)+
	dbf d1,.copy
	lea TR_RNG_MICROS(a2),a4
	move.l a4,$22(a1)
	lea TR_RNG_SECONDS(a2),a4
	move.l a4,$34(a1)
	moveq #0,d0
	bra .done
.bad:
	moveq #-1,d0
.done:
	movem.l (sp)+,d1/a0-a4
	rts
