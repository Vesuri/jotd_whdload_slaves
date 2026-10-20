; Capture after normal world effects; non-deadline fields check guided release.
; Retained command completion uses the same callback. Script-modal completion
; stays suspended; normal activation seeds a fresh lifecycle prediction.
; a0=arena. Return 0/-3, preserve non-result registers.
timing_runtime_actors:
 cmpi.l #1,RT_READY(a0)
 bne .bad
 tst.w RT_BOUNDARY_PHASE(a0)
 bne .retained
 cmpi.w #1,RT_CAPTURE_OWNER(a0)
 bne .bad
 bra .owner
.retained:
 cmpi.w #4,RT_BOUNDARY_PHASE(a0)
 bne .bad
 tst.w RT_CAPTURE_OWNER(a0)
 bne .bad
.owner:
 cmpi.w #3,RT_CONSUMER+TF_PHASE(a0)
 bne .bad
 tst.w RT_SCHEDULER+TS_STATE(a0)
 beq timing_runtime_actor_release
 cmpi.w #2,RT_BODY+WB_PHASE(a0)
 bne .bad
 cmpi.w #2,RT_SCHEDULER+TS_STATE(a0)
 bne .bad
 cmpi.w #1,RT_SCHEDULER+TS_DUE(a0)
 bne .bad
 move.l d1,-(sp)
 move.l RT_SCHEDULER+TS_FIELD(a0),d1
 cmp.l RT_RECORD+TR_FIELD(a0),d1
 bne .bad_saved
 cmp.l RT_CONSUMER+TF_FIELD(a0),d1
 bne .bad_saved
 tst.w RT_ACTOR_PRESENT+AC_VALID(a0)
 beq .fresh
 move.l RT_CLOCK+TC_TICKS(a0),d1
 cmp.l RT_ACTOR_PRESENT+AC_TICK(a0),d1
 beq .bad_saved
.fresh:
 move.l (sp)+,d1
 bsr timing_runtime_actors_seed
 tst.l d0
 bne .return
 bra timing_runtime_script_seed
.return:
 rts
.bad_saved:
 move.l (sp)+,d1
.bad:
 moveq #-3,d0
 rts

; Internal: normal activation or the checked post-world callback only.
; Stable prepared bindings, phase0..2; no gameplay callbacks or publication.
timing_runtime_actors_seed:
 clr.w RT_RELEASE_PRESENT+AC_VALID(a0)
 movem.l d1/a0-a3,-(sp)
 move.l RT_CLOCK+TC_TICKS(a0),d0
 moveq #0,d1
 move.w RT_CLOCK+TC_PHASE(a0),d1
 lea RT_ACTOR_PREVIEW(a0),a1
 lea RT_ACTOR_GENERATIONS(a0),a2
 movea.l RT_HUNKS+24(a0),a3
 adda.w #$3b88,a3
 lea RT_ACTOR_PRESENT(a0),a0
 bsr actor_present_capture
 movem.l (sp)+,d1/a0-a3
 rts

; Non-deadline field completion. Native guidance has just run in field order.
; There is one native guided slot; constructors replacing it run on world
; ticks, which reset this separate release cache. Other actors keep their
; original world-anchored predictions, avoiding a visual jump on release.
timing_runtime_actor_release:
 movem.l d1-d7/a0-a6,-(sp)
 movea.l a0,a6
 tst.w RT_SCHEDULER+TS_DUE(a6)
 bne .bad
 move.l RT_SCHEDULER+TS_FIELD(a6),d1
 cmp.l RT_RECORD+TR_FIELD(a6),d1
 bne .bad
 cmp.l RT_CONSUMER+TF_FIELD(a6),d1
 bne .bad
 cmpi.w #1,RT_ACTOR_PRESENT+AC_VALID(a6)
 bne .done
 move.l RT_CLOCK+TC_TICKS(a6),d0
 cmp.l RT_ACTOR_PRESENT+AC_TICK(a6),d0
 bne .done
 tst.w RT_RELEASE_PRESENT+AC_VALID(a6)
 bne .done
 moveq #0,d1
 move.w RT_CLOCK+TC_PHASE(a6),d1
 cmp.w RT_CLOCK+TC_RATE(a6),d1
 bhs .bad
 movea.l RT_HUNKS(a6),a0
 adda.l #$ba08,a0
 move.w 6(a0),d7 ; native guided slot, -1 means absent
 cmpi.w #5,d7
 bhi .done
 move.w (a0),d2
 and.w 4(a0),d2
 btst d7,d2
 beq .done
 move.w RT_ACTOR_PRESENT+AC_MASKS+2(a6),d2
 btst d7,d2
 bne .done ; already eligible at the world snapshot
 move.w RT_ACTOR_PRESENT+AC_MASKS(a6),d2
 btst d7,d2
 beq .done ; no captured constructor identity
 move.w d7,d3
 lsl.w #2,d3
 lea RT_ACTOR_GENERATIONS(a6),a0
 lea RT_ACTOR_PRESENT+AC_GENERATIONS(a6),a1
 move.l 0(a0,d3.w),d2
 cmp.l 0(a1,d3.w),d2
 bne .done
 move.w AG_EXHAUSTED(a0),d2
 or.w AG_EXHAUSTED(a1),d2
 btst d7,d2
 bne .done
 ; Fresh snapshot begins exactly at this delivered release field. Motion
 ; bytes are copied now, after guidance; world state remains untouched.
 lea RT_RELEASE_PRESENT(a6),a0
 lea RT_ACTOR_PREVIEW(a6),a1
 lea RT_ACTOR_GENERATIONS(a6),a2
 movea.l RT_HUNKS+24(a6),a3
 adda.w #$3b88,a3
 bsr actor_present_capture
 tst.l d0
 bne .exit
 moveq #0,d2
 bset d7,d2
 and.w d2,RT_RELEASE_PRESENT+AC_SAFE(a6)
.done:
 moveq #0,d0
 bra .exit
.bad:
 moveq #-3,d0
.exit:
 movem.l (sp)+,d1-d7/a0-a6
 rts

; Internal post-world capture only. A matching target raster must exist; no
; activation/menu bitmap is eligible. Foreground excludes renderer and swaps.
timing_runtime_script_seed:
 movem.l d1-d7/a0-a6,-(sp)
 movea.l a0,a6
 clr.w RT_SCRIPT_PRESENT+SPC_VALID(a6)
 cmpi.w #2,RT_TARGET_PHASE(a6)
 bne .done
 move.l RT_TARGET_FIELD(a6),d0
 cmp.l RT_RECORD+TR_FIELD(a6),d0
 bne .done
 movea.l RT_HUNKS+24(a6),a3
 movea.l RT_SCRIPT_BITMAP(a6),a4
 move.l a4,d0
 beq .done
 cmpa.l $47c4(a3),a4
 bne .done
 ; Any late world blit must finish before CPU pixel reads. Do not retain a
 ; pixel dependency after this call: the next frame may reuse the buffer.
 tst.w $dff002
.wait:
 btst #6,$dff002
 bne .wait
 adda.w #$3b88,a3
 lea RT_TARGET+WT_PALETTE+24(a6),a5
 lea RT_SCRIPT_PRESENT(a6),a0
 lea RT_SCRIPT_PREVIEW(a6),a1
 lea RT_SCRIPT_GENERATION(a6),a2
 move.l RT_CLOCK+TC_TICKS(a6),d0
 moveq #0,d1
 move.w RT_CLOCK+TC_PHASE(a6),d1
 bsr script_present_capture
 tst.l d0
 bmi .exit
.done:
 moveq #0,d0
.exit:
 movem.l (sp)+,d1-d7/a0-a6
 rts
