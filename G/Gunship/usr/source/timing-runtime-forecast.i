; Private forecast workspace setup. Called only during runtime preparation,
; before the loader cache flush and before any timing producer is active.
; a0=arena; 0/negative rejection, non-result registers preserved.
timing_runtime_forecast_prepare:
 movem.l d1-d7/a0-a6,-(sp)
 movea.l a0,a6
 adda.l #RT_FORECAST,a6
 movea.l RT_HUNKS(a0),a4
 movea.l RT_HUNKS+16(a0),a1
 movea.l RT_HUNKS+24(a0),a5
 adda.w #$1c8,a1
 lea $7a44(a4),a0
 lea RF_SINE(a6),a2
 bsr forecast_sine_prepare
 tst.l d0
 bne .done
 movea.l a4,a0
 lea RF_STAGES(a6),a1
 bsr motion_stages_prepare
 tst.l d0
 bne .done
 movea.l a1,a0
 lea $7a44(a4),a1
 lea RF_SINE(a6),a2
 bsr forecast_stages_bind_sine
 tst.l d0
 bne .done
 movea.l a4,a0
 lea RF_GROUND(a6),a1
 movea.l a5,a2
 lea RF_EVENT(a6),a3
 bsr ground_deferred_prepare
 tst.l d0
 bne .done
 ; Preparation and every accepted lifecycle transition retire the tape.
 ; Fixed epoch 1 is safe only with that unconditional invalidation protocol.
 move.l #1,RF_CONTEXT(a6)
 clr.l RF_CONTEXT+4(a6)
 lea RF_STAGES(a6),a0
 move.l a0,RF_CONTEXT+8(a6)
 lea RF_SINE(a6),a0
 move.l a0,RF_CONTEXT+12(a6)
 lea RF_GROUND(a6),a0
 move.l a0,RF_CONTEXT+16(a6)
 clr.l RF_CONTEXT+20(a6)
 clr.l RF_EVENT(a6)
 lea RF_TAPE(a6),a0
 bsr forecast_tape_reset
.done:
 movem.l (sp)+,d1-d7/a0-a6
 rts

; a0=arena. Retire before suspended storage can be reused or released.
; Clear only prediction publication and its private deferred event.
timing_runtime_forecast_reset:
 move.l a0,-(sp)
 adda.l #RT_FORECAST,a0
 clr.l RF_EVENT(a0)
 adda.w #RF_TAPE,a0
 bsr forecast_tape_reset
 movea.l (sp)+,a0
 rts

; a0=prepared arena at a drained presentation boundary, foreground serialized.
; Return 0 reused, 1 built, -3 rejected. RF_PLAYER is valid only on success.
; Holds current directions, predicts zero future impulses. Does not publish
; player/scene state or commit an event. Preserve all non-result registers.
timing_runtime_forecast_get:
 movem.l d1-d7/a0-a6,-(sp)
 movea.l a0,a6
 cmpi.l #1,RT_READY(a6)
 bne .bad
 cmpi.w #1,RT_CAPTURE_OWNER(a6)
 bne .bad
 cmpi.w #2,RT_VIEW_PHASE(a6)
 beq .bad
 tst.w RT_BOUNDARY_PHASE(a6)
 bne .bad
 tst.w RT_BATCH(a6)
 bne .bad
 tst.w RT_SCHEDULER+TS_STATE(a6)
 bne .bad
 tst.w RT_SCHEDULER+TS_FIELDS(a6)
 bne .bad
 tst.w RT_SCHEDULER+TS_EXCESS(a6)
 bne .bad
 move.w RT_SCHEDULER+TS_FAULT(a6),d0
 or.w RT_HISTORY+TH_FAULT(a6),d0
 or.w RT_COMMANDS+CQ_FAULT(a6),d0
 or.w RT_CLOCK+TC_FAULT(a6),d0
 bne .bad
 cmpi.w #1,RT_CLOCK+TC_ACTIVE(a6)
 bne .bad
 cmpi.w #1,RT_HISTORY+TH_ACTIVE(a6)
 bne .bad
 cmpi.w #1,RT_COMMANDS+CQ_ACTIVE(a6)
 bne .bad
 moveq #0,d2
 move.w RT_CLOCK+TC_RATE(a6),d2
 cmpi.w #50,d2
 beq .rate
 cmpi.w #60,d2
 bne .bad
.rate:
 cmp.w RT_ENDPOINT+EP_DELAY+CD_RATE(a6),d2
 bne .bad
 moveq #0,d3
 move.w RT_CLOCK+TC_PHASE(a6),d3
 cmp.w d2,d3
 bhs .bad
 sub.w d3,d2
 addq.w #2,d2
 divu.w #3,d2
 move.w RT_ENDPOINT+EP_DONE(a6),d4
 cmp.w RT_ENDPOINT+EP_SPAN(a6),d4
 bhi .bad
 move.l RT_CLOCK+TC_TICKS(a6),d1
 addq.l #1,d1
 andi.l #$ffff,d1
 cmp.w RT_ENDPOINT+EP_SPAN(a6),d4
 beq .copy
 cmp.w RT_ENDPOINT+EP_TICK(a6),d1
 bne .bad
 move.w RT_ENDPOINT+EP_SPAN(a6),d5
 sub.w d4,d5
 cmp.w d2,d5
 bne .bad
.copy:
 movea.l a6,a5
 adda.l #RT_FORECAST,a5
 lea RT_ENDPOINT(a6),a0
 lea RF_OWNER(a5),a1
 moveq #EP_SIZE/4-1,d0
.owner:
 move.l (a0)+,(a1)+
 dbf d0,.owner
 movea.l RT_HUNKS+24(a6),a2
 adda.w #$3b88,a2
 cmp.w RT_ENDPOINT+EP_SPAN(a6),d4
 bne .active
 ; At a completed interval, start only a private copy for the next deadline.
 ; ceil((rate-phase)/3) yields PAL 17/17/16 and NTSC 20 at world boundaries.
 moveq #0,d0
 move.w d2,d0
 lea RF_OWNER(a5),a0
 movea.l a2,a1
 bsr endpoint_player_begin
 tst.l d0
 bne .bad
.active:
 move.l RT_CLOCK+TC_TICKS(a6),RF_CONTEXT+4(a5)
 clr.l RF_EVENT(a5) ; discard only a previous speculative ground decision
 lea RF_TAPE(a5),a0
 lea RF_OWNER(a5),a1
 lea RT_PACKET(a6),a3
 lea RF_CONTEXT(a5),a4
 lea RF_EVENT(a5),a6
 move.l a6,d0
 lea RF_PLAYER(a5),a6
 lea RF_WORK(a5),a5
 bsr forecast_player_get
 bra .done
.bad:
 moveq #-3,d0
.done:
 movem.l (sp)+,d1-d7/a0-a6
 rts
