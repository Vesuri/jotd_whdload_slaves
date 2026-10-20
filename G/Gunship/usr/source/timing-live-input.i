; Runtime-backed native capture for experimental TIMING_RUNTIME builds.
; Same displaced ABI as diagnostic input, without its $7f rearm behavior.
; Marker layout in RT_CAPTURE matches h0/h2/history/sample at +8..20,
; sequence/raw deltas/edges at +24..36, FIFO owner +38, sampler +40, queue +44.
; RT_SAMPLE is producer-private; RT_RECORD belongs only to the consumer.
;
; a0=prepared arena, a2=resload. Validate all sites before patching any.
; Return 0/-1, preserve other registers. Sampling remains paused at install.
timing_live_install:
 movem.l d1-d7/a0-a6,-(sp)
 move.l _custom1(pc),d0
 beq .disabled
 cmpi.l #1,RT_READY(a0)
 bne .bad
 movea.l RT_HUNKS(a0),a1
 cmpi.w #$4eb9,$fa0(a1)
 bne .bad
 lea $1068(a1),a3
 cmpa.l $fa2(a1),a3
 bne .bad
 cmpi.l #$3228000a,$fc6(a1)
 bne .bad
 cmpi.w #$4841,$fca(a1)
 bne .bad
 cmpi.l #$31860800,$34c8(a1)
 bne .bad
 cmpi.w #$7056,$34cc(a1)
 bne .bad
 cmpi.w #$2a39,$4dc6(a1)
 bne .bad
 movea.l RT_HUNKS+8(a0),a4
 adda.w #$10,a4
 cmpa.l $4dc8(a1),a4
 bne .bad
 lea timing_runtime_sampler(pc),a4
 move.l a3,(a4)
 lea .patches(pc),a0
 jsr resload_Patch(a2)
.disabled:
 moveq #0,d0
 bra .done
.bad:
 moveq #-1,d0
.done:
 movem.l (sp)+,d1-d7/a0-a6
 rts
.patches:
 PL_START
 PL_PS $fa0,timing_live_field
 PL_PS $fc6,timing_live_mouse
 PL_PS $34c8,timing_live_command
 PL_PS $4dc6,timing_live_fire
 PL_END

timing_live_field:
	bsr timing_live_original
	move.w sr,-(sp)
	movem.l d0-d2/a0-a2,-(sp)
	movea.l timing_runtime_arena(pc),a2
	lea RT_CAPTURE(a2),a2
	tst.w RT_BOUNDARY_PHASE-RT_CAPTURE(a2)
	bne .boundary
.capture:
	movea.l 12(a2),a0
	movea.l 20(a2),a1
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
	movea.l 16(a2),a0
	tst.w TH_ACTIVE(a0)
	beq .publish
	move.w #1,TH_FAULT(a0)
.publish:
	movea.l 44(a2),a0
	tst.w CQ_FAULT(a0)
	beq .commands_ok
	movea.l 16(a2),a0
	tst.w TH_ACTIVE(a0)
	beq .commands_ok
	move.w #1,TH_FAULT(a0)
.commands_ok:
	move.w 36(a2),TR_EDGES(a1)
	clr.l 28(a2)
	clr.l 32(a2)
	movea.l 16(a2),a0
	bsr history_publish
.restore:
	movem.l (sp)+,d0-d2/a0-a2
	move.w (sp)+,ccr
	rts
.boundary:
	; A retained field may be finishing with its consumers temporarily active.
	; UI-time input never enters that old epoch; native sampling still ran.
	clr.l 28(a2)
	clr.l 32(a2)
	bra .restore

timing_live_original:
	move.l timing_runtime_sampler(pc),-(sp)
	rts

; Retain raw signed input-event deltas before native scaling/filtering.
; ADDA avoids changing X; the displaced MOVE/SWAP recreates native NZVC.
timing_live_mouse:
	movem.l d0/a1-a2,-(sp)
	movea.l timing_runtime_arena(pc),a2
	lea RT_CAPTURE(a2),a2
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
; across payload publication/cutoff update. Preserve
; X portably (including on 68000 in user mode); MOVEQ recreates native NZVC.
timing_live_command:
	move.w d6,(a0,d0.l)
	movem.l d0-d1/a0-a2/a6,-(sp)
	moveq #0,d0
	addx.b d0,d0
	move.w d0,-(sp)
	movea.l 4.w,a6
	jsr _LVODisable(a6)
	movea.l timing_runtime_arena(pc),a2
	lea RT_CAPTURE(a2),a2
	move.l 24(a2),d0
	addq.l #1,d0
	move.l d0,24(a2)
	tst.w RT_BOUNDARY_PHASE-RT_CAPTURE(a2)
	bne .recorded
	movea.l 44(a2),a0
	move.w d6,d1
	bsr commands_publish
	cmpi.l #1,d0
	bne .recorded
	; Retire only a successfully retained key under explicit flight ownership.
	; Modal/native ownership leaves the original FIFO completely intact.
	cmpi.w #1,38(a2)
	bne .recorded
	movea.l 16(a2),a0
	tst.w TH_ACTIVE(a0)
	beq .recorded
	tst.w TH_FAULT(a0)
	bne .recorded
	; Saved native d0 is the appended slot's byte offset; saved a0 is
	; the ten-word FIFO base. Native count is the longword at base+22.
	; The saved X word precedes the MOVEM frame throughout this section.
	move.l 2(sp),d1
	cmpi.l #18,d1
	bhi .fifo_bad
	btst #0,d1
	bne .fifo_bad
	movea.l 10(sp),a1
	move.l 22(a1),d0
	tst.l d0
	beq .fifo_bad
	cmpi.l #10,d0
	bhi .fifo_bad
	subq.l #1,d0
	add.l d0,d0
	cmp.l d1,d0
	bne .fifo_bad
	cmp.w 0(a1,d1.l),d6
	bne .fifo_bad
	clr.w 0(a1,d1.l)
	subq.l #1,22(a1)
	bra .recorded
.fifo_bad:
	; No speculative repair or FIFO shift. Recovery owns the retained key.
	move.w #1,TH_FAULT(a0)
	movea.l 44(a2),a0
	move.w #1,CQ_FAULT(a0)
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
timing_live_fire:
	movem.l d0-d1/a0-a1,-(sp)
	movea.l timing_runtime_arena(pc),a1
	lea RT_CAPTURE(a1),a1
	movea.l 12(a1),a0
	move.l $10(a0),d0
	movea.l 8(a1),a0
	move.w $4e2a(a0),d1
	eor.w d1,d0
	movea.l 12(a1),a0
	and.w $12(a0),d0
	move.w d0,36(a1)
	movem.l (sp)+,d0-d1/a0-a1
	move.l a0,-(sp)
	movea.l timing_runtime_arena(pc),a0
	movea.l RT_HUNKS+8(a0),a0
	move.l $10(a0),d5
	movea.l (sp)+,a0
	rts

 even
timing_runtime_sampler: dc.l 0
