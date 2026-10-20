; Native 0658 world-tick opening, before HUD/camera/render work.
; Standalone. Once-only scheduling and command ordering belong to the caller.
WS_NATIVE_SIZE equ $98       ; +05640..+056d8
WS_CODE_SIZE equ WS_NATIVE_SIZE+2

; a0=validated hunk 0, a1=even clone, a2=validated hunk 6,
; a3=authoritative player to bind. Buffers must not overlap; flush caches.
; Validate relocated side effects before writing. Return 0/-1, preserve others.
world_start_prepare:
	movem.l d1/a0/a2-a5,-(sp)
	lea $5640(a0),a4
	cmpi.l #$526d000c,(a4)
	bne .bad
	cmpi.w #$4239,$36(a4)
	bne .bad
	lea $1581(a2),a5
	cmpa.l $38(a4),a5
	bne .bad
	cmpi.w #$4239,$3c(a4)
	bne .bad
	lea $1583(a2),a5
	cmpa.l $3e(a4),a5
	bne .bad
	lea $7eee(a0),a5
	cmpi.w #$4eb9,$6e(a4)
	bne .bad
	cmpa.l $70(a4),a5
	bne .bad
	cmpi.w #$4eb9,$8c(a4)
	bne .bad
	cmpa.l $8e(a4),a5
	bne .bad
	lea $3b88(a2),a5
	cmpi.w #$4bf9,$74(a4)
	bne .bad
	cmpa.l $76(a4),a5
	bne .bad
	cmpi.w #$4bf9,$92(a4)
	bne .bad
	cmpa.l $94(a4),a5
	bne .bad
	movea.l a1,a5
	moveq #WS_NATIVE_SIZE/2-1,d1
.copy:
	move.w (a4)+,(a5)+
	dbf d1,.copy
	move.w #$4e75,(a5)
	move.l a3,$76(a1)
	move.l a3,$94(a1)
	moveq #0,d0
	bra .done
.bad:
	moveq #-1,d0
.done:
	movem.l (sp)+,d1/a0/a2-a5
	rts

; a0=bound authoritative player, a1=prepared clone. Return 0/-1.
; Advances tick, cooldowns and engine state; native indicator writes/calls real.
; Never call from presentation or speculative motion. No rollback after entry.
world_start_step:
	movem.l d1-d7/a0-a6,-(sp)
	cmpa.l $76(a1),a0
	bne .bad
	cmpa.l $94(a1),a0
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
