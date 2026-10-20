; Ordered player/world effects of accepted command $0003.
; Standalone; dispatcher/lifecycle installation pending.
CM_SIZE equ 2             ; logical engine-bit-4 state, word 0/1

; a0=mode shadow, a1=player. Initialize at a synchronized command epoch.
; Reinitialize only after outstanding command ownership is resolved/discarded.
control_mode_init:
	move.l d1,-(sp)
	moveq #0,d1
	btst #4,$42(a1)
	beq .store
	moveq #1,d1
.store:
	move.w d1,(a0)
	moveq #0,d0
	movem.l (sp)+,d1
	rts

; a0=mode shadow, a1=player, d0.w=full accepted command word.
; Apply at its field: toggle the logical bit and clear collective if old bit
; was set. Do not alter the authoritative world engine byte.
; Return 1 handled, 0 other command, -1 invalid shadow. Preserve others.
; The continuing-command yaw tail remains the dispatcher's separate duty.
control_mode_command:
	cmpi.w #3,d0
	bne .other
	cmpi.w #1,(a0)
	bhi .bad
	bchg #0,1(a0)
	beq .handled
	clr.b $39(a1)
.handled:
	moveq #1,d0
	rts
.other:
	moveq #0,d0
	rts
.bad:
	moveq #-1,d0
	rts

; a0=player, a1=validated native indicator callback (+0af36),
; d0.w=full command. Apply once in original world-command order.
; Toggle the actual engine bit and invoke the native indicator, but do NOT
; repeat the collective reset or common yaw tail against a later field pose.
; Return 1 handled, 0 other command; other registers preserved.
control_mode_world:
	cmpi.w #3,d0
	bne .other
	movem.l d1-d7/a0-a6,-(sp)
	movea.l a0,a5
	move.b #0,d1
	bchg #4,$42(a5)
	beq .notify
	move.b #2,d1
.notify:
	moveq #14,d0
	jsr (a1)
	movem.l (sp)+,d1-d7/a0-a6
	moveq #1,d0
	rts
.other:
	moveq #0,d0
	rts

; a0=shadow, a1=player. Check only when both readers have reached the SAME
; cutoff and before advancing fields. No repair or silent rebase on mismatch.
; Return 0 equal, -1 invalid/divergent; preserve others.
control_mode_check:
	move.l d1,-(sp)
	moveq #0,d1
	btst #4,$42(a1)
	beq .compare
	moveq #1,d1
.compare:
	moveq #-1,d0
	cmp.w (a0),d1
	bne .done
	moveq #0,d0
.done:
	movem.l (sp)+,d1
	rts
