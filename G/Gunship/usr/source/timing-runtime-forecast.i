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
 ; Separate scene and collector; live target scratch must never be borrowed.
 movea.l a4,a0
 movea.l a5,a1
 lea RF_TARGET(a6),a2
 bsr target_select_prepare
 tst.l d0
 bne .done
 ; Recover native hunk pointers from the arena below the forecast base.
 movea.l a6,a0
 suba.l #RT_FORECAST,a0
 movea.l RT_HUNKS+16(a0),a1
 movea.l RT_HUNKS+24(a0),a2
 movea.l RT_HUNKS(a0),a0
 lea RF_SCENE(a6),a3
 lea RF_TARGET(a6),a4
 lea RF_COLLECTOR(a6),a5
 lea RF_PLAYER(a6),a6
 bsr scene_target_player_prepare
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


; a0=arena, same serialized presentation-boundary contract as forecast_get.
; Collect the held-control forecast view using the CURRENT world model/limits.
; Return 0 for a zero/one-candidate selector in RF_SELECTED, -3 if ambiguous
; or rejected. No bitmap sampling and no promise about future input/impulses.
; The caller must certify that uncertainty before using this to steer a preview.
; Scene/target scratch is private; native target/player state is never written.
timing_runtime_forecast_candidates:
 movem.l d1-d7/a0-a6,-(sp)
 movea.l a0,a6
 bsr timing_runtime_forecast_get
 tst.l d0
 bmi .bad
 movea.l a6,a0
 bsr timing_runtime_forecast_collect
 bra .done
.bad:
 moveq #-3,d0
.done:
 movem.l (sp)+,d1-d7/a0-a6
 rts

; Internal: caller already admitted serialized foreground state. RF_PLAYER
; is a private candidate; collect it without replacing it with the zero case.
timing_runtime_forecast_collect:
 movem.l d1-d7/a0-a6,-(sp)
 movea.l a0,a6
 movea.l a6,a5
 adda.l #RT_FORECAST,a5
 lea RF_PLAYER(a5),a0
 lea RF_CAMERA(a5),a2
 bsr native_camera_build
 movea.l RT_HUNKS(a6),a0
 adda.l #$a99e,a0
 lea RF_TARGET+WT_STATE(a5),a1
 moveq #WT_STATE_SIZE/4-1,d1
.seed:
 move.l (a0)+,(a1)+
 dbf d1,.seed
 lea RF_SCENE(a5),a0
 lea RF_CAMERA(a5),a1
 movea.l RT_HUNKS(a6),a2
 adda.l #$c6a0,a2
 bsr scene_target_candidates_step
 tst.l d0
 bne .bad
 lea RF_TARGET(a5),a0
 lea RF_SELECTED(a5),a1
 bsr target_selector_single
 bra .done
.bad:
 moveq #-3,d0
.done:
 movem.l (sp)+,d1-d7/a0-a6
 rts

; a0=arena. Return 0 only when every eligible native impulse combination
; yields the same unambiguous selector; RF_CERTIFIED then holds its 12 bytes.
; Return -3 otherwise. All forecast records are scratch, status is mandatory.
; Holds controls and current world geometry fixed; NOT a future-input proof.
; Enumerate native impulse eligibility without calling or advancing RNG.
timing_runtime_forecast_certify:
 movem.l d1-d7/a0-a6,-(sp)
 movea.l a0,a6
 bsr timing_runtime_forecast_candidates
 tst.l d0
 bne .bad
 movea.l a6,a5
 adda.l #RT_FORECAST,a5
 lea RF_SELECTED(a5),a0
 lea RF_CERTIFIED(a5),a1
 move.l (a0)+,(a1)+
 move.l (a0)+,(a1)+
 move.l (a0),(a1)
 ; The last stored checkpoint precedes the world deadline by one field.
 moveq #0,d0
 move.w RF_TAPE+FCT_COUNT(a5),d0
 subq.w #1,d0
 mulu.w #FC_SIZE,d0
 lea RF_TAPE+FCT_RECORDS(a5),a4
 adda.l d0,a4
 lea FC_PLAYER(a4),a0
 moveq #0,d7
 btst #0,$0f(a0)
 beq .pitch
 moveq #4,d7
.pitch:
 moveq #0,d6
 tst.b $1c(a0)
 bne .heading
 cmpi.w #8,$2a(a0)
 blo .heading
 move.b $1d(a0),d0
 cmp.b $2b(a0),d0
 bhs .heading
 moveq #1,d6
.heading:
 moveq #0,d5
 tst.w $1c(a0)
 beq .ranges
 move.w $0e(a0),d0
 andi.w #3,d0
 beq .ranges
 moveq #2,d5
.ranges:
 move.w d7,d4
 neg.w d4
.roll:
 move.w d6,d3
 neg.w d3
.pitch_loop:
 move.w d5,d2
 neg.w d2
.heading_loop:
 move.w d4,d0
 or.w d3,d0
 or.w d2,d0
 beq .next ; zero impulse was already checked
 movea.l a4,a0
 lea RF_OWNER(a5),a1
 moveq #EP_SIZE/2-1,d0
.owner:
 move.w (a0)+,(a1)+
 dbf d0,.owner
 lea RF_PLAYER(a5),a1
 moveq #MP_RECORD_SIZE/2-1,d0
.player:
 move.w (a0)+,(a1)+
 dbf d0,.player
 lea RF_WORK+FB_PACKET(a5),a1
 move.l (a0),(a1)
 move.w d4,4(a1)
 move.w d3,6(a1)
 move.w d2,8(a1)
 lea RF_OWNER(a5),a0
 move.l EP_DELAY+CD_FIELD(a0),d0
 addq.l #1,d0
 ; a4 is retained across calls, so save its checkpoint pointer temporarily.
 move.l a4,-(sp)
 lea RF_PLAYER(a5),a1
 lea RF_STAGES(a5),a2
 lea RF_SINE(a5),a3
 lea RF_WORK+FB_PACKET(a5),a4
 bsr endpoint_player_step
 tst.l d0
 bne .bad_saved
 clr.l RF_EVENT(a5)
 lea RF_GROUND(a5),a3
 lea RF_EVENT(a5),a4
 bsr endpoint_ground_resolve
 tst.l d0
 bmi .bad_saved
 movea.l (sp)+,a4
 movea.l a6,a0
 bsr timing_runtime_forecast_collect
 tst.l d0
 bne .bad
 lea RF_SELECTED(a5),a0
 lea RF_CERTIFIED(a5),a1
 moveq #2,d0
.compare:
 cmpm.l (a0)+,(a1)+
 bne .bad
 dbf d0,.compare
.next:
 addq.w #1,d2
 cmp.w d5,d2
 ble .heading_loop
 addq.w #1,d3
 cmp.w d6,d3
 ble .pitch_loop
 addq.w #4,d4
 cmp.w d7,d4
 ble .roll
 moveq #0,d0
 bra .done
.bad_saved:
 movea.l (sp)+,a4
.bad:
 moveq #-3,d0
.done:
 movem.l (sp)+,d1-d7/a0-a6
 rts
