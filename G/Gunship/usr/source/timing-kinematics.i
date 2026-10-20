; Ordered continuous flight step. Requires motion-stages, flight-rates,
; heading and movement includes. Standalone; native installation is pending.
; Attitude/control commands precede this step; world decisions remain outside.
KN_FLIGHT equ 0
KN_HEADING equ KN_FLIGHT+FR_SIZE
KN_MOVEMENT equ KN_HEADING+HG_SIZE
KN_SIZE equ KN_MOVEMENT+MV_SIZE
; Transaction scratch on stack: shadows, player, native terms, old angles/RPM.
KN_PLAYER equ KN_SIZE
KN_TERMS equ KN_PLAYER+MP_RECORD_SIZE
KN_OLD_H equ KN_TERMS+MS_TERMS_SIZE
KN_OLD_T equ KN_OLD_H+2
KN_OLD_RPM equ KN_OLD_T+2
KN_IMPULSE equ KN_OLD_RPM+2
KN_SCRATCH equ KN_IMPULSE+4

; a0=KN_SIZE state, d0=50/60 (3 only for whole-tick fixtures).
; d0=0/-1; preserves all other registers. Invalid rate leaves state unchanged.
kinematics_init:
	movem.l d1/a0,-(sp)
	cmpi.l #50,d0
	beq .valid
	cmpi.l #60,d0
	beq .valid
	cmpi.l #3,d0
	bne .bad
.valid:
	move.l d0,d1
	bsr flight_rates_init
	adda.w #KN_HEADING,a0
	move.l d1,d0
	bsr heading_init
	adda.w #HG_SIZE,a0
	move.l d1,d0
	bsr movement_init
	bra .done
.bad:
	moveq #-1,d0
.done:
	movem.l (sp)+,d1/a0
	rts

; a0=state, a1=player, a2=prepared immutable motion stages,
; a3=validated native sine helper, d0=world heading impulse (-2..2).
; Native stage buffers/table must be validated and instruction caches flushed
; before calling. Buffers must not overlap state/player or this stack.
; The caller supplies the logical interval's tick parity in player+$0c.
; Returns d0=0/-1; preserves all other registers. On failure neither player
; nor shadow state is committed. No RNG, commands, contact or clock updates.
kinematics_step:
	movem.l d1-d7/a0-a6,-(sp)
	suba.w #KN_SCRATCH,sp
	movea.l sp,a4
	movea.l a0,a5
	movea.l a1,a6
	move.l a2,d6
	move.l a3,d7
	move.l d0,KN_IMPULSE(a4)
	; Reject mismatched component rates even if individually valid.
	move.w FR_RATE(a5),d1
	cmp.w KN_HEADING+HG_RATE(a5),d1
	bne .bad
	cmp.w KN_MOVEMENT+MV_RATE(a5),d1
	bne .bad
	movea.l a4,a2
	moveq #KN_SIZE/2-1,d1
.copy_state:
	move.w (a0)+,(a2)+
	dbf d1,.copy_state
	moveq #MP_RECORD_SIZE/2-1,d1
.copy_player:
	move.w (a1)+,(a2)+
	dbf d1,.copy_player
	clr.l KN_TERMS(a4)
	clr.l KN_TERMS+4(a4)
	clr.l KN_TERMS+8(a4)
	moveq #0,d0
	move.b KN_PLAYER+$35(a4),d0
	move.w d0,KN_OLD_H(a4)
	move.b KN_PLAYER+$3d(a4),d0
	move.w d0,KN_OLD_T(a4)
	moveq #0,d0
	bsr .stage
	lea KN_HEADING(a4),a0
	lea KN_PLAYER(a4),a1
	moveq #0,d0
	move.w KN_OLD_H(a4),d0
	moveq #0,d1
	move.w KN_OLD_T(a4),d1
	move.l KN_IMPULSE(a4),d2
	bsr heading_step
	tst.l d0
	bne .bad
	moveq #1,d0
	bsr .stage
	lea KN_FLIGHT(a4),a0
	lea KN_PLAYER(a4),a1
	lea KN_TERMS(a4),a2
	bsr flight_vertical_step
	tst.l d0
	bne .bad
	lea KN_MOVEMENT(a4),a0
	bsr movement_height
	tst.l d0
	bne .bad
	moveq #3,d0
	bsr .stage
	lea KN_FLIGHT(a4),a0
	lea KN_PLAYER(a4),a1
	lea KN_TERMS(a4),a2
	bsr flight_forward_step
	tst.l d0
	bne .bad
	lea KN_MOVEMENT(a4),a0
	movea.l d7,a2
	bsr movement_horizontal
	tst.l d0
	bne .bad
	moveq #0,d0
	move.b KN_PLAYER+$1b(a4),d0
	move.w d0,KN_OLD_RPM(a4)
	moveq #6,d0
	bsr .stage
	lea KN_FLIGHT(a4),a0
	lea KN_PLAYER(a4),a1
	moveq #0,d0
	move.w KN_OLD_RPM(a4),d0
	bsr flight_rpm_step
	tst.l d0
	bne .bad
	; Publish only a complete successful candidate (foreground use only).
	movea.l a4,a0
	moveq #KN_SIZE/2-1,d1
.commit_state:
	move.w (a0)+,(a5)+
	dbf d1,.commit_state
	moveq #MP_RECORD_SIZE/2-1,d1
.commit_player:
	move.w (a0)+,(a6)+
	dbf d1,.commit_player
	moveq #0,d0
	bra .done
.bad:
	moveq #-1,d0
.done:
	adda.w #KN_SCRATCH,sp
	movem.l (sp)+,d1-d7/a0-a6
	rts
.stage:
	lea KN_PLAYER(a4),a0
	movea.l d6,a1
	lea KN_TERMS(a4),a2
	bra motion_stage
