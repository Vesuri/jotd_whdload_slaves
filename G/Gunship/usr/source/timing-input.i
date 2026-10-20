; Native 0658 field producer. Diagnostic installation only (VERIFY+TIMING_INPUT).
; Raw key $7f requests a fresh diagnostic capture at the next active VBL.
; This key has no dedicated native action, but still runs its shared yaw tail.
; No foreground game consumer is installed yet. Native input/FIFO/latch
; behaviour is retained.
; Accepted native commands are retained for independent player/world readers.
; Their effect classification and foreground hand-off are not installed yet.

timing_input_install:
	move.l _custom1(pc),d0
	bne .enabled
	rts
.enabled:
	movea.l verify_marker+8(pc),a1
	; Validate every displaced instruction before modifying any of these sites.
	cmpi.w #$4eb9,$fa0(a1)
	bne wrong_version
	lea $1068(a1),a0
	cmpa.l $fa2(a1),a0
	bne wrong_version
	cmpi.l #$3228000a,$fc6(a1)
	bne wrong_version
	cmpi.w #$4841,$fca(a1)
	bne wrong_version
	cmpi.l #$31860800,$34c8(a1)
	bne wrong_version
	cmpi.w #$7056,$34cc(a1)
	bne wrong_version
	cmpi.w #$2a39,$4dc6(a1)
	bne wrong_version
	movea.l verify_marker+16(pc),a0
	lea $10(a0),a0
	cmpa.l $4dc8(a1),a0
	bne wrong_version
	lea timing_input_marker(pc),a0
	move.l a1,8(a0)
	move.l verify_marker+16(pc),12(a0)
	lea timing_input_history(pc),a3
	move.l a3,16(a0)
	lea timing_input_sample(pc),a3
	move.l a3,20(a0)
	lea timing_input_commands(pc),a3
	move.l a3,44(a0)
	clr.l 24(a0)
	clr.l 28(a0)
	clr.l 32(a0)
	clr.l 36(a0)
	lea $1068(a1),a3
	move.l a3,40(a0)
	lea timing_input_history(pc),a0
	moveq #0,d0
	bsr history_init
	bsr history_pause
	lea timing_input_commands(pc),a0
	moveq #0,d0
	bsr commands_init
	bsr commands_pause
	lea timing_input_patches(pc),a0
	jsr resload_Patch(a2)
	rts

timing_input_patches:
	PL_START
	PL_PS $fa0,timing_input_field
	PL_PS $fc6,timing_input_mouse
	PL_PS $34c8,timing_input_command
	PL_PS $4dc6,timing_input_fire
	PL_END

; Called only at the active-screen VBL call site, after native smoothing.
; Preserve the native sampler's complete result, including CCR. This site
; executes in the supervisor VBL server, so MOVE SR is legal on all CPUs.
timing_input_field:
	bsr timing_input_original
	move.w sr,-(sp)
	movem.l d0-d2/a0-a2,-(sp)
	lea timing_input_marker(pc),a2
	tst.w 38(a2)
	beq .capture
	clr.w 38(a2)
	movea.l 12(a2),a0
	move.l $1c(a0),d0
	subq.l #1,d0
	lea timing_input_history(pc),a0
	bsr history_init
.capture:
	movea.l 12(a2),a0
	lea timing_input_sample(pc),a1
	move.l $1c(a0),TR_FIELD(a1)
	move.l $08(a0),TR_X(a1)
	move.l $0c(a0),TR_Y(a1)
	move.l $10(a0),TR_BUTTONS(a1)
	move.l $14(a0),TR_RNG_SECONDS(a1)
	move.l $18(a0),TR_RNG_MICROS(a1)
	move.l $2a(a0),TR_RELATIVE(a1)
	move.l 24(a2),TR_COMMAND(a1)
	movea.l 8(a2),a0
	moveq #0,d0
	move.b $c8c(a0),d0
	move.w d0,TR_MODE(a1)
	move.l 28(a2),d0
	move.w d0,TR_DX(a1)
	move.w d0,d1
	ext.l d1
	cmp.l d0,d1
	bne .delta_overflow
	move.l 32(a2),d0
	move.w d0,TR_DY(a1)
	move.w d0,d1
	ext.l d1
	cmp.l d0,d1
	beq .publish
.delta_overflow:
	; Never publish silently truncated relative motion.
	lea timing_input_history(pc),a0
	tst.w TH_ACTIVE(a0)
	beq .publish
	move.w #1,TH_FAULT(a0)
.publish:
	lea timing_input_commands(pc),a0
	tst.w CQ_FAULT(a0)
	beq .commands_ok
	lea timing_input_history(pc),a0
	move.w #1,TH_FAULT(a0)
.commands_ok:
	move.w 36(a2),TR_EDGES(a1)
	clr.l 28(a2)
	clr.l 32(a2)
	lea timing_input_history(pc),a0
	bsr history_publish
	movem.l (sp)+,d0-d2/a0-a2
	move.w (sp)+,ccr
	rts

timing_input_original:
	move.l timing_input_marker+40(pc),-(sp)
	rts

; Retain raw signed input-event deltas before native scaling/filtering.
; ADDA avoids changing X; the displaced MOVE/SWAP recreates native NZVC.
timing_input_mouse:
	movem.l d0/a1-a2,-(sp)
	lea timing_input_marker(pc),a2
	move.w 10(a0),d0
	ext.l d0
	movea.l 28(a2),a1
	adda.l d0,a1
	move.l a1,28(a2)
	move.w 12(a0),d0
	ext.l d0
	movea.l 32(a2),a1
	adda.l d0,a1
	move.l a1,32(a2)
	movem.l (sp)+,d0/a1-a2
	move.w 10(a0),d1
	swap d1
	rts

; Retain accepted FIFO insertions, not key-up or native overflow. Exclude VBL
; across payload publication/cutoff update and diagnostic rearming. Preserve
; X portably (including on 68000 in user mode); MOVEQ recreates native NZVC.
timing_input_command:
	move.w d6,(a0,d0.l)
	movem.l d0-d1/a0-a2/a6,-(sp)
	moveq #0,d0
	addx.b d0,d0
	move.w d0,-(sp)
	movea.l 4.w,a6
	jsr _LVODisable(a6)
	lea timing_input_marker(pc),a2
	move.l 24(a2),d0
	addq.l #1,d0
	move.l d0,24(a2)
	lea timing_input_commands(pc),a0
	cmpi.w #$7f,d6
	bne .retain
	bsr commands_init
	move.w #1,38(a2)
	bra .recorded
.retain:
	move.w d6,d1
	bsr commands_publish
.recorded:
	jsr _LVOEnable(a6)
	move.w (sp)+,d0
	lsr.b #1,d0
	movem.l (sp)+,d0-d1/a0-a2/a6
	moveq #$56,d0
	rts

; Fire uses the preceding field's held buttons, before the new sample.
; Record exactly that rising-edge mask, including edges the native latch
; subsequently clears because its consumer flags are set.
timing_input_fire:
	movem.l d0-d1/a0-a1,-(sp)
	lea timing_input_marker(pc),a1
	movea.l 12(a1),a0
	move.l $10(a0),d0
	movea.l 8(a1),a0
	move.w $4e2a(a0),d1
	eor.w d1,d0
	movea.l 12(a1),a0
	and.w $12(a0),d0
	move.w d0,36(a1)
	movem.l (sp)+,d0-d1/a0-a1
	move.l timing_input_marker+12(pc),d5
	; Replay MOVE.L (hunk2+$10),d5 without borrowing another register.
	move.l a0,-(sp)
	movea.l d5,a0
	move.l $10(a0),d5
	movea.l (sp)+,a0
	rts

	even
timing_input_marker:
	dc.b "GSIH0002"
	dc.l 0,0,0,0             ; hunk0, hunk2, history, sample
	dc.l 0,0,0               ; accepted command sequence, raw x/y
	dc.w 0,0                 ; native fire edges, diagnostic arm request
	dc.l 0                   ; native joystick sampler
	dc.l 0                   ; retained command queue (extension at +44)
timing_input_history:
	ds.b TH_SIZE
timing_input_sample:
	ds.b TH_RECORD_SIZE
timing_input_commands:
	ds.b CQ_SIZE

	IFND TH_SIZE
	include "timing-history.i"
	ENDC
	IFND CQ_SIZE
	include "timing-commands.i"
	ENDC
