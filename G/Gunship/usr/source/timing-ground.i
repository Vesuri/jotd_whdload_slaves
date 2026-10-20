; World-owned native ground consequences, extracted without rewriting policy.
; Standalone; not installed. The caller schedules this once per world tick
; after height and before forward speed, displacement and RPM (native order).
GR_NATIVE_SIZE equ $96       ; +095a0..+09636
GR_CODE_SIZE equ GR_NATIVE_SIZE+2

; a0=validated 0658 hunk 0, a1=even destination, a2=validated hunk 6.
; d0=0/-1; other registers preserved. No destination writes on mismatch.
; Buffers must not overlap; flush instruction caches before execution.
ground_prepare:
	movem.l d1/a0/a2-a4,-(sp)
	movea.l a0,a3
	adda.l #$95a0,a3
	cmpi.l #$4a026700,(a3)
	bne .bad
	cmpi.w #$0082,4(a3)
	bne .bad
	cmpi.w #$4eb9,$48(a3)
	bne .bad
	movea.l a0,a4
	adda.l #$a150,a4
	cmpa.l $4a(a3),a4
	bne .bad
	cmpi.l #$13fc00b4,$54(a3)
	bne .bad
	adda.l #$42f6,a2
	cmpa.l $58(a3),a2
	bne .bad
	cmpi.l #$422d003e,$86(a3)
	bne .bad
	cmpi.l #$426d002a,$8a(a3)
	bne .bad
	cmpi.l #$422d0037,$8e(a3)
	bne .bad
	cmpi.l #$422d0036,$92(a3)
	bne .bad
	movea.l a1,a4
	moveq #GR_NATIVE_SIZE/2-1,d1
.copy:
	move.w (a3)+,(a4)+
	dbf d1,.copy
	move.w #$4e75,(a4)
	moveq #0,d0
	bra .done
.bad:
	moveq #-1,d0
.done:
	movem.l (sp)+,d1/a0/a2-a4
	rts

; a0=authoritative player, a1=prepared native ground block,
; d0=pre-height airborne flag (0/1), supplied by the world hand-off.
; d0=1 reset applied, 0 airborne/no action, -1 invalid flag/no writes.
; Preserves other registers; native notifications and timer writes are real.
; This is NOT a preview: do not invoke from render or speculative field work.
; Caller must clear associated vertical/speed/attitude fractional state when
; return is 1, before later motion stages. Contact eligibility/history and
; once-only scheduling are caller responsibilities, not inferred here.
ground_step:
	movem.l d1-d7/a0-a6,-(sp)
	cmpi.l #1,d0
	bhi .bad
	tst.w $1c(a0)
	bne .airborne
	move.l d0,d2
	movea.l a0,a5
	jsr (a1)
	moveq #1,d0
	bra .done
.airborne:
	moveq #0,d0
	bra .done
.bad:
	moveq #-1,d0
.done:
	movem.l (sp)+,d1-d7/a0-a6
	rts
