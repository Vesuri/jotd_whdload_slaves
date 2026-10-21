; Native 0658 full-word command classification and field reader.
; Requires commands, control-targets and control-mode. Not installed.
CC_PLAYER equ 1
CC_MODE equ 2
CC_WORLD equ 3
CC_BOUNDARY equ 4

; d0.w=accepted word. Return class above, or 0 for native unknown/no primary.
; Preserve other registers; never mask modifier bits.
control_command_class:
	movem.l d1-d2/a0,-(sp)
	move.w d0,d2
	moveq #0,d0
	lea .classes(pc),a0
	moveq #(.end-.classes)/4-1,d1
.scan:
	cmp.w (a0),d2
	beq .found
	addq.l #4,a0
	dbf d1,.scan
	bra .done
.found:
	move.w 2(a0),d0
.done:
	tst.l d0
	movem.l (sp)+,d1-d2/a0
	rts
.classes:
	dc.w $4c,CC_PLAYER,$4d,CC_PLAYER,$4e,CC_PLAYER,$4f,CC_PLAYER
	dc.w $50,CC_PLAYER,$5a,CC_PLAYER,$51,CC_PLAYER,$5b,CC_PLAYER
	dc.w $52,CC_PLAYER,$5c,CC_PLAYER,$53,CC_PLAYER,$5d,CC_PLAYER
	dc.w $38,CC_PLAYER,$39,CC_PLAYER,$3a,CC_PLAYER
	dc.w $03,CC_MODE
	dc.w $01,CC_WORLD,$02,CC_WORLD,$04,CC_WORLD,$05,CC_WORLD
	dc.w $06,CC_WORLD,$07,CC_WORLD,$08,CC_WORLD,$09,CC_WORLD
	dc.w $0a,CC_WORLD,$0b,CC_WORLD,$804,CC_WORLD,$805,CC_WORLD
	dc.w $806,CC_WORLD
	; Key $0c retires the old speed toggle: default tail-only consumption.
	; It must not enter a lifecycle boundary or discard the current phase.
	dc.w $45,CC_BOUNDARY,$833,CC_BOUNDARY
	dc.w $40,CC_BOUNDARY,$1c,CC_BOUNDARY,$41,CC_BOUNDARY
	dc.w $37,CC_BOUNDARY,$21,CC_BOUNDARY,$22,CC_BOUNDARY
	dc.w $34,CC_BOUNDARY,$42,CC_BOUNDARY,$46,CC_BOUNDARY
.end:

CP_QUEUE equ 0
CP_PLAYER equ 4
CP_MODE equ 8
CP_SEQUENCE equ 12
CP_KEY equ 16
CP_COMMITTED equ 18
CP_APPLIED equ 20
CP_SIZE equ 24

; a0=context: initialize three pointers and zero remaining fields.
; d0=recorded field command cutoff. Process at most one player-reader command.
; Return 1 applied/acknowledged, 0 none due, 2 lifecycle/display boundary,
; or negative queue/state error. World reader is never advanced here.
; CP_COMMITTED distinguishes effects applied before an acknowledgement fault.
; Boundary commands remain retained, with sequence/key available to the owner.
; A paused lifecycle owner's completion marker skips native effects and tail;
; both readers still acknowledge independently. Other marker values reject.
control_player_next:
	movem.l d1-d7/a0-a6,-(sp)
	suba.w #8,sp
	movea.l a0,a6
	clr.w CP_COMMITTED(a6)
	movea.l CP_QUEUE(a6),a0
	movea.l sp,a1
	moveq #0,d1
	bsr commands_peek
	cmpi.l #1,d0
	bne .done
	move.l (sp),CP_SEQUENCE(a6)
	move.w 4(sp),CP_KEY(a6)
	moveq #0,d0
	move.w 4(sp),d0
	bsr control_command_class
	tst.w 6(sp)
	beq .unhandled
	cmpi.w #CQ_BOUNDARY_DONE,6(sp)
	bne .bad_record
	cmpi.l #CC_BOUNDARY,d0
	bne .bad_record
	bra .acknowledge
.unhandled:
	cmpi.l #CC_BOUNDARY,d0
	beq .boundary
	cmpi.l #CC_MODE,d0
	beq .mode
	cmpi.l #CC_PLAYER,d0
	bne .tail
	movea.l CP_PLAYER(a6),a0
	move.w 4(sp),d0
	bsr control_target_command
	bra .tail
.mode:
	movea.l CP_MODE(a6),a0
	movea.l CP_PLAYER(a6),a1
	move.w 4(sp),d0
	bsr control_mode_command
	tst.l d0
	bmi .done
.tail:
	; Unknown and world-primary commands also have a field-owned yaw tail.
	movea.l CP_PLAYER(a6),a0
	bsr control_target_tail
.acknowledge:
	move.w #1,CP_COMMITTED(a6)
	addq.l #1,CP_APPLIED(a6)
	movea.l CP_QUEUE(a6),a0
	movea.l sp,a1
	moveq #0,d1
	bsr commands_ack
	tst.l d0
	bne .done
	; A command was just applied; pause/empty cannot mean "nothing happened".
	moveq #-1,d0
	bra .done
.boundary:
	moveq #2,d0
	bra .done
.bad_record:
	moveq #-3,d0
.done:
	adda.w #8,sp
	movem.l (sp)+,d1-d7/a0-a6
	rts
