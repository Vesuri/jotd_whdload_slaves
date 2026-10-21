; Continuous control + flight composition. Requires attitude and kinematics.
; Standalone, not installed. Commands must already be applied in their
; scheduled order. Pitch clamp precedes stick/motion; no world decisions.
; Word-aligned state/record copies use 16-byte groups and exact tails;
; an 86-byte record must never read or write the following two bytes.
PS_ATTITUDE equ 0
PS_KINEMATICS equ AT_SIZE
PS_SIZE equ AT_SIZE+KN_SIZE
PS_PLAYER equ PS_SIZE
PS_SCRATCH equ PS_SIZE+MP_RECORD_SIZE
; Immutable input packet: signed words x, y, roll impulse, pitch impulse,
; heading impulse. Directions -1..1; impulses -4/0/4, -1..1 and -2..2.
PS_INPUT_SIZE equ 10

; a0=state, d0=rate 50/60 (3 whole-tick fixture), d1=previous y (-1..1).
; d0=0/-1, other registers preserved; invalid inputs leave state unchanged.
player_step_init:
	movem.l d2/a0,-(sp)
	move.l d0,d2
	bsr attitude_init
	tst.l d0
	bne .done
	adda.w #PS_KINEMATICS,a0
	move.l d2,d0
	bsr kinematics_init
.done:
	movem.l (sp)+,d2/a0
	rts

; a0=state, a1=player, a2=prepared native motion stages,
; a3=native sine helper, a4=PS_INPUT_SIZE immutable packet.
; Returns d0=0/-1, other registers preserved. Copies back only on success.
; Caller owns input-history decoding, validated/non-overlapping buffers,
; logical tick parity, world-impulse eligibility and cache synchronization.
player_step:
	movem.l d1-d7/a0-a6,-(sp)
	move.l a4,d5
	move.l a2,d6
	move.l a3,d7
	suba.w #PS_SCRATCH,sp
	movea.l sp,a4
	movea.l a0,a5
	movea.l a1,a6
	move.w AT_RATE(a5),d0
	cmp.w PS_KINEMATICS+FR_RATE(a5),d0
	bne .bad
	movea.l a4,a2
	moveq #PS_SIZE/16-1,d0
.copy_state:
	REPT 4
	move.l (a0)+,(a2)+
	ENDR
	dbf d0,.copy_state
	REPT PS_SIZE/4-(PS_SIZE/16)*4
	move.l (a0)+,(a2)+
	ENDR
	IFNE PS_SIZE&2
	move.w (a0)+,(a2)+
	ENDC
	moveq #MP_RECORD_SIZE/16-1,d0
.copy_player:
	REPT 4
	move.l (a1)+,(a2)+
	ENDR
	dbf d0,.copy_player
	REPT MP_RECORD_SIZE/4-(MP_RECORD_SIZE/16)*4
	move.l (a1)+,(a2)+
	ENDR
	IFNE MP_RECORD_SIZE&2
	move.w (a1)+,(a2)+
	ENDC
	lea PS_ATTITUDE(a4),a0
	lea PS_PLAYER(a4),a1
	movea.l d5,a2
	bsr attitude_pitch_clamp_control
	tst.l d0
	bne .bad
	movea.l d5,a2
	move.w (a2),d0
	ext.l d0
	move.w 2(a2),d1
	ext.l d1
	move.w 4(a2),d2
	ext.l d2
	move.w 6(a2),d3
	ext.l d3
	bsr attitude_step_impulses
	tst.l d0
	bne .bad
	move.w 8(a2),d0
	ext.l d0
	lea PS_KINEMATICS(a4),a0
	movea.l d6,a2
	movea.l d7,a3
	move.l AT_PITCH_REMAINDER(a4),d1
	bsr kinematics_step_fractional
	tst.l d0
	bne .bad
	movea.l a4,a0
	moveq #PS_SIZE/16-1,d0
.commit_state:
	REPT 4
	move.l (a0)+,(a5)+
	ENDR
	dbf d0,.commit_state
	REPT PS_SIZE/4-(PS_SIZE/16)*4
	move.l (a0)+,(a5)+
	ENDR
	IFNE PS_SIZE&2
	move.w (a0)+,(a5)+
	ENDC
	moveq #MP_RECORD_SIZE/16-1,d0
.commit_player:
	REPT 4
	move.l (a0)+,(a6)+
	ENDR
	dbf d0,.commit_player
	REPT MP_RECORD_SIZE/4-(MP_RECORD_SIZE/16)*4
	move.l (a0)+,(a6)+
	ENDR
	IFNE MP_RECORD_SIZE&2
	move.w (a0)+,(a6)+
	ENDC
	moveq #0,d0
	bra .done
.bad:
	moveq #-1,d0
.done:
	adda.w #PS_SCRATCH,sp
	movem.l (sp)+,d1-d7/a0-a6
	rts

; Same pointers as player_step, plus d0=logical interval tick (0..65535).
; Use the upcoming world interval's parity without advancing player+$0c.
; The native world owner remains the sole writer of the authoritative clock.
; Return d0=0/-1, other registers preserved. Foreground/serialized use only.
player_step_interval:
	cmpi.l #65535,d0
	bhi .bad
	movem.l d1-d2/a1/a5-a6,-(sp)
	move.l d0,d2
	movea.l a1,a6
	suba.w #MP_RECORD_SIZE,sp
	movea.l sp,a5
	moveq #MP_RECORD_SIZE/16-1,d1
.copy:
	REPT 4
	move.l (a1)+,(a5)+
	ENDR
	dbf d1,.copy
	REPT MP_RECORD_SIZE/4-(MP_RECORD_SIZE/16)*4
	move.l (a1)+,(a5)+
	ENDR
	IFNE MP_RECORD_SIZE&2
	move.w (a1)+,(a5)+
	ENDC
	movea.l sp,a1
	move.w d2,$0c(a1)
	bsr player_step
	tst.l d0
	bne .done
	movea.l sp,a5
	move.w $0c(a6),$0c(a5)
	moveq #MP_RECORD_SIZE/16-1,d1
.commit:
	REPT 4
	move.l (a5)+,(a6)+
	ENDR
	dbf d1,.commit
	REPT MP_RECORD_SIZE/4-(MP_RECORD_SIZE/16)*4
	move.l (a5)+,(a6)+
	ENDR
	IFNE MP_RECORD_SIZE&2
	move.w (a5)+,(a6)+
	ENDC
.done:
	adda.w #MP_RECORD_SIZE,sp
	movem.l (sp)+,d1-d2/a1/a5-a6
	rts
.bad:
	moveq #-1,d0
	rts
