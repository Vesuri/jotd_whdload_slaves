; Candidate-only ground evaluation, followed by explicit side-effect commit.
; Requires ground and player-ground definitions. Standalone, not installed.
GD_SIZE equ 4             ; notification.w, timer.b, ready.b
GD_READY equ 3

; ground_prepare arguments plus a3=stable private GD_SIZE-byte event record.
; d0=0/-1; others preserved. Caller owns buffers and instruction-cache flush.
ground_deferred_prepare:
	move.l a0,-(sp)
	bsr ground_prepare
	tst.l d0
	bne .done
	; Replace JSR notification with MOVE.W D0,absolute (both six bytes).
	; The preceding native MOVEQ supplies 7. The native notification preserves
	; registers, and the following MOVE.B overwrites its condition codes.
	move.w #$33c0,$48(a1)
	move.l a3,$4a(a1)
	lea 2(a3),a0
	move.l a0,$58(a1)
.done:
	movea.l (sp)+,a0
	rts

; a0=candidate PS shadow, a1=candidate player, a2=deferred ground clone,
; a3=the same event record bound at preparation, d0=airborne flag (0/1).
; Return player_ground_step status; preserve others. No live side effects.
; An event must be empty before evaluation; discard it explicitly if its
; candidate fails. No implicit overwrite of a pending successful decision.
ground_deferred_step:
	cmpi.l #1,d0
	bhi .bad
	tst.l (a3)
	bne .bad
	bsr player_ground_step
	tst.l d0
	bmi .done
	move.b #1,GD_READY(a3)
.done:
	rts
.bad:
	moveq #-1,d0
	rts

; a0=event, a1=validated native notification entry, a2=native timer byte.
; Call only after candidate motion has successfully completed and published.
; Return 1 effects applied, 0 valid empty decision, -1 invalid/not ready.
; Consume before calling out: a second commit cannot repeat the notification.
; This cannot fail after consumption; world scheduling/lifecycle is caller-owned.
ground_deferred_commit:
	movem.l d1-d7/a0-a6,-(sp)
	cmpi.l #$00000001,(a0)
	beq .empty
	cmpi.l #$0007b401,(a0)
	bne .bad
	clr.l (a0)
	moveq #7,d0
	jsr (a1)
	move.b #$b4,(a2)
	moveq #1,d0
	bra .done
.empty:
	clr.l (a0)
	moveq #0,d0
	bra .done
.bad:
	moveq #-1,d0
.done:
	movem.l (sp)+,d1-d7/a0-a6
	rts
