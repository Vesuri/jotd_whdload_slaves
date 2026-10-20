; Publish latest player/certified forward-actor inputs for one native +05c04 frame.
; No old +04288 interpolation loop, gameplay writes, RNG or graphics calls.
; a0=arena. Caller serializes foreground state and presentation readers during
; publication. Return 0, -3 invalid admission, -1 invalid camera fractions.
; Preserve non-result registers. Failed camera validation touches private
; scratch only; no native input buffers are published until all builders pass.
timing_runtime_present_state:
 movem.l d1-d7/a0-a6,-(sp)
 movea.l a0,a6
 cmpi.l #1,RT_READY(a6)
 bne .bad
 cmpi.w #2,RT_VIEW_PHASE(a6)
 beq .bad
 cmpi.w #1,RT_CAPTURE_OWNER(a6)
 bne .bad
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
 movea.l RT_HUNKS+24(a6),a5
 ; Preserve native holes and externally owned instrument bytes. The source
 ; starts at an odd address; byte copies are required on the 68000.
 lea $157d(a5),a0
 lea RT_PRESENT_INSTRUMENTS(a6),a1
 moveq #15,d1
.instrument_seed:
 move.b (a0)+,(a1)+
 dbf d1,.instrument_seed
 lea $3b88(a5),a0
 lea RT_PRESENT_INSTRUMENTS(a6),a1
 lea RT_CAMERA(a6),a2
 movea.l RT_HUNKS+16(a6),a3
 adda.w #$1c8,a3
 bsr presentation_build
 lea RT_ENDPOINT(a6),a1
 bsr endpoint_camera_angles
 tst.l d0
 bne .done
 lea RT_ACTOR_PRESENT(a6),a0
 lea RT_ACTOR_GENERATIONS(a6),a1
 lea RT_ACTOR_COORDS(a6),a2
 move.l RT_CLOCK+TC_TICKS(a6),d0
 moveq #0,d1
 move.w RT_CLOCK+TC_PHASE(a6),d1
 moveq #0,d2
 move.w RT_CLOCK+TC_RATE(a6),d2
 bsr actor_present_build
 tst.l d0
 bmi .done
 ; The guided release cache owns at most the native guided slot. Its first
 ; fraction starts at release; unaffected actors retain world anchoring.
 lea RT_RELEASE_PRESENT(a6),a0
 lea RT_ACTOR_GENERATIONS(a6),a1
 lea RT_RELEASE_COORDS(a6),a2
 move.l RT_CLOCK+TC_TICKS(a6),d0
 moveq #0,d1
 move.w RT_CLOCK+TC_PHASE(a6),d1
 moveq #0,d2
 move.w RT_CLOCK+TC_RATE(a6),d2
 bsr actor_present_build
 tst.l d0
 bmi .done
 moveq #5,d1
.release_slots:
 btst d1,d0
 beq .release_next
 move.w d1,d2
 add.w d2,d2
 lea RT_RELEASE_COORDS(a6),a0
 adda.w d2,a0
 lea RT_ACTOR_COORDS(a6),a1
 adda.w d2,a1
 move.w (a0),(a1)
 move.w 12(a0),12(a1)
 move.w 24(a0),24(a1)
.release_next:
 dbf d1,.release_slots
 lea RT_CAMERA(a6),a0
 lea RT_ACTOR_COORDS(a6),a1
 movea.l a5,a2
 lea RT_PRESENT_SCENE(a6),a3
 bsr scene_state_build
 lea RT_SCRIPT_PRESENT(a6),a0
 lea RT_SCRIPT_GENERATION(a6),a1
 lea RT_PRESENT_SCENE+48(a6),a2
 lea $3b88(a5),a3
 move.l RT_CLOCK+TC_TICKS(a6),d0
 moveq #0,d1
 move.w RT_CLOCK+TC_PHASE(a6),d1
 moveq #0,d2
 move.w RT_CLOCK+TC_RATE(a6),d2
 bsr script_present_build
 tst.l d0
 bmi .done
 ; Reset capture before any native presentation publication. The frame uses
 ; this committed identity, while projected coordinates come from rendering.
 lea RT_VIEW(a6),a0
 movea.l RT_HUNKS(a6),a1
 adda.l #$a99e,a1
 bsr target_view_reset
 tst.l d0
 bne .done
 move.w #1,RT_VIEW_PHASE(a6)
 ; Keep native current/previous endpoint caches coherent for native UI.
 lea RT_PRESENT_SCENE(a6),a0
 movea.l RT_HUNKS+16(a6),a1
 movea.l RT_HUNKS+20(a6),a2
 adda.w #10,a2
 lea $3904(a5),a3
 moveq #26,d1
.scene:
 move.w (a0)+,d0
 move.w d0,(a1)+
 move.w d0,(a2)+
 move.w d0,(a3)+
 dbf d1,.scene
 lea RT_CAMERA(a6),a0
 movea.l RT_HUNKS+20(a6),a1
 addq.l #4,a1
 moveq #2,d1
.position:
 move.w (a0)+,(a1)+
 dbf d1,.position
 lea RT_PRESENT_INSTRUMENTS(a6),a0
 lea $157d(a5),a1
 moveq #15,d1
.instruments:
 move.b (a0)+,(a1)+
 dbf d1,.instruments
 lea RT_PRESENT_INSTRUMENTS+7(a6),a0
 movea.l RT_HUNKS+16(a6),a1
 lea $40(a1),a2
 adda.w #$36,a1
 moveq #8,d1
.gauge_cache:
 move.b (a0)+,d0
 move.b d0,(a1)+
 move.b d0,(a2)+
 dbf d1,.gauge_cache
 moveq #0,d0
 bra .done
.bad:
 moveq #-3,d0
.done:
 movem.l (sp)+,d1-d7/a0-a6
 rts
