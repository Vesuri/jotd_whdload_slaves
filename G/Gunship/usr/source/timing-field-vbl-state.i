; Gameplay-visible timer/guidance state from native VBL +04b48..+04c38.
; Requires field-guidance. Standalone; original VBL owners must be excluded
; on installation. Cosmetic RNG, sound, counters and drawing stay separate.
; a0=hunk 6, a1=hunk 4, a2=prepared guidance clone. Return 1 evaluated,
; 0 inactive (negative quit byte), -1 mismatched guidance binding, preserve rest.
field_vbl_state:
	movem.l a0-a3,-(sp)
	lea $1c6(a1),a3
	cmpa.l FG_QUIT(a2),a3
	bne .bad
	tst.b (a3)
	bmi .inactive
	movea.l a0,a3
	tst.b $4296(a3)
	beq .ground
	subq.b #1,$4296(a3)
.ground:
	tst.b $42f6(a3)
	beq .guidance
	subq.b #1,$42f6(a3)
.guidance:
	movea.l a2,a0
	bsr field_guidance_advance
	tst.b $42f7(a3)
	beq .evaluated
	subq.b #1,$42f7(a3)
.evaluated:
	moveq #1,d0
	bra .done
.inactive:
	moveq #0,d0
	bra .done
.bad:
	moveq #-1,d0
.done:
	movem.l (sp)+,a0-a3
	rts

SF_SCHEDULER equ 0
SF_HUNK6 equ 4
SF_HUNK4 equ 8
SF_GUIDANCE equ 12
SF_FIELD equ 16
SF_VALID equ 20
SF_COMMITTED equ 22
SF_SIZE equ 24

; a0=context (four pointers, metadata zeroed on epoch initialization).
; Run before controls/deadline opening, replacing scheduled_guidance_step.
; Return 0/1 evaluated status, -1 fault/binding, -3 wrong/duplicate phase.
; A producer fault after effects retains FIELD/VALID and COMMITTED=1.
; No scheduler acknowledgement. Explicit lifecycle rebase is caller-owned.
scheduled_field_vbl_state:
	movem.l d1-d2/a0-a3,-(sp)
	movea.l a0,a3
	clr.w SF_COMMITTED(a3)
	movea.l SF_SCHEDULER(a3),a0
	cmpi.w #1,TS_STATE(a0)
	bne .phase
	bsr scheduler_check
	tst.l d0
	bmi .done
	move.l TS_FIELD(a0),d2
	tst.w SF_VALID(a3)
	beq .apply
	cmp.l SF_FIELD(a3),d2
	beq .phase
.apply:
	movea.l SF_HUNK6(a3),a0
	movea.l SF_HUNK4(a3),a1
	movea.l SF_GUIDANCE(a3),a2
	bsr field_vbl_state
	tst.l d0
	bmi .done
	move.l d0,d1
	move.l d2,SF_FIELD(a3)
	move.w #1,SF_VALID(a3)
	move.w #1,SF_COMMITTED(a3)
	movea.l SF_SCHEDULER(a3),a0
	bsr scheduler_check
	tst.l d0
	bmi .done
	move.l d1,d0
	bra .done
.phase:
	moveq #-3,d0
.done:
	movem.l (sp)+,d1-d2/a0-a3
	rts
