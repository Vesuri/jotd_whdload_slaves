; Ground consequence hand-off for the combined player state.
; Requires player-step and ground definitions. Standalone, not installed.
;
; a0 = initialized PS_SIZE shadow, a1 = authoritative player,
; a2 = prepared ground block, d0 = world-selected pre-height airborne flag.
; Return 1 reset, 0 airborne, -1 invalid flag; preserve all other registers.
; Run once at the world boundary AFTER height, BEFORE forward/displacement/RPM.
; Native notifications/timer writes are real; this is not a speculative step.
; The caller owns contact eligibility and guarantees all storage is valid.
player_ground_step:
	movem.l a0-a3,-(sp)
	movea.l a0,a3
	movea.l a1,a0
	movea.l a2,a1
	bsr ground_step
	cmpi.l #1,d0
	bne .done
	; Native ground resets pitch, roll, vertical velocity and forward speed.
	; Discard their fractional debt too, or motion would reappear next field.
	clr.l PS_ATTITUDE+AT_ROLL_REMAINDER(a3)
	clr.l PS_ATTITUDE+AT_PITCH_REMAINDER(a3)
	clr.l PS_KINEMATICS+KN_FLIGHT+FR_VERTICAL(a3)
	clr.l PS_KINEMATICS+KN_FLIGHT+FR_FORWARD(a3)
	clr.l PS_KINEMATICS+KN_FLIGHT+FR_FORWARD_CONV(a3)
	; A committed ground contact snaps sub-unit altitude to the ground.
	clr.l PS_KINEMATICS+KN_MOVEMENT+MV_HEIGHT(a3)
	clr.w PS_KINEMATICS+KN_MOVEMENT+MV_CONTACT(a3)
	; Keep control history, heading/track, RPM and horizontal fractions.
	; MV_WAS_AIRBORNE remains the latest height step's provenance.
.done:
	movem.l (sp)+,a0-a3
	rts
