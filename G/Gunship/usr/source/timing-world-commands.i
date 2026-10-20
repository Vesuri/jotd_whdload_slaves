; Native world-primary command decoder, excluding the field-owned yaw tail.
; Requires command-dispatch/control-mode definitions. Standalone, not installed.
WC_CODE_SIZE equ $462      ; +04ed4..+05334 inclusive
WC_TAIL equ $3f8           ; native +052cc
WC_POST_TAIL equ $426      ; native +052fa

; a0=validated 0658 code hunk, a1=even WC_CODE_SIZE-byte destination.
; Validate patch boundaries before writes; caller owns version/non-overlap
; checks and instruction-cache flush. Return 0/-1, preserve others.
world_commands_prepare:
	movem.l d1/a0/a2,-(sp)
	lea $4ed4(a0),a0
	cmpi.l #$0c470045,(a0)
	bne .bad
	cmpi.l #$102d003f,WC_TAIL(a0)
	bne .bad
	cmpi.l #$0c470804,WC_POST_TAIL(a0)
	bne .bad
	cmpi.w #$4e75,WC_CODE_SIZE-2(a0)
	bne .bad
	movea.l a1,a2
	move.w #WC_CODE_SIZE/2-1,d1
.copy:
	move.w (a0)+,(a2)+
	dbf d1,.copy
	; Leave all relative positions intact, including post-tail 0804..0806.
	move.l #$6000002c,WC_TAIL(a1)
	moveq #0,d0
	bra .done
.bad:
	moveq #-1,d0
.done:
	movem.l (sp)+,d1/a0/a2
	rts

; a0=player, a1=prepared decoder, a2=native indicator (+0af36),
; d0.w=full accepted command. Call once through the world reader.
; Return 1 applied world primary, 0 no world effect, 2 retained boundary.
; Preserve other registers. Never call the clone directly with arbitrary
; keys: lifecycle exits have native stack semantics unsuitable here.
world_command_step:
	movem.l d1-d7/a0-a6,-(sp)
	move.w d0,d7
	bsr control_command_class
	cmpi.l #CC_BOUNDARY,d0
	beq .boundary
	cmpi.l #CC_MODE,d0
	beq .mode
	cmpi.l #CC_WORLD,d0
	bne .none
	movea.l a0,a5
	jsr (a1)
	moveq #1,d0
	bra .done
.mode:
	movea.l a2,a1
	move.w d7,d0
	bsr control_mode_world
	bra .done
.boundary:
	moveq #2,d0
	bra .done
.none:
	moveq #0,d0
.done:
	movem.l (sp)+,d1-d7/a0-a6
	rts

CW_QUEUE equ 0
CW_PLAYER equ 4
CW_DECODER equ 8
CW_INDICATOR equ 12
CW_SEQUENCE equ 16
CW_KEY equ 20
CW_COMMITTED equ 22
CW_APPLIED equ 24
CW_SIZE equ 28

; a0=context, d0=world deadline's recorded command cutoff.
; Initialize four pointers and zero remaining fields. Process one command.
; Return 1 processed/acknowledged, 0 none due, 2 retained boundary, or error.
; Field-primary/unknown commands are acknowledged without replaying effects.
; COMMITTED records completed dispatch before ack (including no-op dispatch);
; APPLIED counts processed ordinary commands for recovery accounting.
; Never advance the player cursor. Lifecycle/serialization is caller-owned.
control_world_next:
	movem.l d1-d7/a0-a6,-(sp)
	suba.w #8,sp
	movea.l a0,a6
	clr.w CW_COMMITTED(a6)
	movea.l CW_QUEUE(a6),a0
	movea.l sp,a1
	moveq #1,d1
	bsr commands_peek
	cmpi.l #1,d0
	bne .done
	move.l (sp),CW_SEQUENCE(a6)
	move.w 4(sp),CW_KEY(a6)
	movea.l CW_PLAYER(a6),a0
	movea.l CW_DECODER(a6),a1
	movea.l CW_INDICATOR(a6),a2
	moveq #0,d0
	move.w 4(sp),d0
	bsr world_command_step
	cmpi.l #2,d0
	beq .done
	tst.l d0
	bmi .done
	move.w #1,CW_COMMITTED(a6)
	addq.l #1,CW_APPLIED(a6)
	movea.l CW_QUEUE(a6),a0
	movea.l sp,a1
	moveq #1,d1
	bsr commands_ack
	tst.l d0
	bne .done
	moveq #-1,d0
.done:
	adda.w #8,sp
	movem.l (sp)+,d1-d7/a0-a6
	rts
