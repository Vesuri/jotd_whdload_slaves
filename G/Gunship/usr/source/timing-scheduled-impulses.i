; Retain once-generated motion disturbances across rejected player publication.
; Requires scheduler, history and world-motion-impulses. Not installed.
SI_SCHEDULER equ 0
SI_PLAYER equ 4
SI_RNG equ 8
SI_PACKET equ 12
SI_RECORD equ 16
SI_FIELD equ 20
SI_COMMAND equ 24
SI_VALID equ 28
SI_COMMITTED equ 30
SI_CACHE equ 32
SI_SIZE equ 38

; a0=context: five stable pointers, remaining bytes zero at lifecycle start.
; Call after deadline opening and command application, before player preview.
; Return 0 newly generated, 1 cached packet restored, -1 producer fault,
; -3 wrong phase/record/cutoff. Preserve other registers.
; Cache only the three impulse words: decoded X/Y remain caller-owned.
; COMMITTED means this call generated a packet (drawing RNG if eligible),
; even if the post-check fails.
; FIELD/COMMAND/VALID and cache survive failure. Recovery may restore these
; impulses without consuming RNG again; never reset VALID merely to retry.
; Caller binds the RNG clone to RECORD and owns serialization/lifecycle.
scheduled_motion_impulses:
	movem.l d1-d3/a0-a3,-(sp)
	suba.w #PS_INPUT_SIZE,sp
	movea.l a0,a3
	clr.w SI_COMMITTED(a3)
	movea.l SI_SCHEDULER(a3),a0
	cmpi.w #1,TS_STATE(a0)
	bne .phase
	cmpi.w #1,TS_DUE(a0)
	bne .phase
	movea.l SI_RECORD(a3),a1
	move.l TS_FIELD(a0),d2
	cmp.l TR_FIELD(a1),d2
	bne .phase
	move.l TS_COMMAND(a0),d3
	cmp.l TR_COMMAND(a1),d3
	bne .phase
	bsr scheduler_check
	tst.l d0
	bmi .done
	; Both command owners must have applied this deadline's cutoff before
	; eligibility is inspected. Merely looking must not release a command.
	movea.l SI_SCHEDULER(a3),a0
	movea.l TS_COMMANDS(a0),a0
	movea.l sp,a1
	move.l d3,d0
	moveq #0,d1
	bsr commands_peek
	tst.l d0
	bmi .done
	bne .phase
	move.l d3,d0
	moveq #1,d1
	bsr commands_peek
	tst.l d0
	bmi .done
	bne .phase
	tst.w SI_VALID(a3)
	beq .generate
	cmp.l SI_FIELD(a3),d2
	bne .generate
	cmp.l SI_COMMAND(a3),d3
	bne .phase
	moveq #1,d1
	bra .restore_packet
.generate:
	movea.l SI_PLAYER(a3),a0
	movea.l sp,a1
	movea.l SI_RNG(a3),a2
	bsr world_motion_impulses
	move.l 4(sp),SI_CACHE(a3)
	move.w 8(sp),SI_CACHE+4(a3)
	move.l d2,SI_FIELD(a3)
	move.l d3,SI_COMMAND(a3)
	move.w #1,SI_VALID(a3)
	move.w #1,SI_COMMITTED(a3)
	moveq #0,d1
.restore_packet:
	movea.l SI_PACKET(a3),a1
	move.l SI_CACHE(a3),4(a1)
	move.w SI_CACHE+4(a3),8(a1)
	movea.l SI_SCHEDULER(a3),a0
	bsr scheduler_check
	tst.l d0
	bmi .done
	move.l d1,d0
	bra .done
.phase:
	moveq #-3,d0
.done:
	adda.w #PS_INPUT_SIZE,sp
	movem.l (sp)+,d1-d3/a0-a3
	rts
