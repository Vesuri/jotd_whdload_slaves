; Runtime-wide lifecycle, after allocation/preparation and cache flush.
; Caller excludes producer AND consumers for the entire call. These helpers
; do not disable interrupts themselves and are not native flight hooks.
; Never abandon pending player/world effects or a failed consumer implicitly.

; a0=arena. Return 0/-3; preserve other registers. Keep pending work intact.
timing_runtime_suspend:
 cmpi.l #1,RT_READY(a0)
 bne .bad
 move.l a0,-(sp)
 lea RT_SCHEDULER(a0),a0
 bsr timing_suspend
 movea.l (sp)+,a0
 clr.w RT_CAPTURE_OWNER(a0)
 moveq #0,d0
 rts
.bad:
 moveq #-3,d0
 rts

; a0=arena. Return 0/-3, invalid requests write nothing.
; Resume normal play only: native player/mission must already be ready.
; Read fresh native field/Y and accepted command sequence under exclusion.
; Discard native menu/pause FIFO keys with accounting; do not apply them again.
; Native FIFO/context binding must still be the supported game's hunk 6.
timing_runtime_activate:
 movem.l d1-d7/a0-a6,-(sp)
 movea.l a0,a6
 cmpi.l #1,RT_READY(a6)
 bne .bad
 cmpi.w #2,RT_VIEW_PHASE(a6)
 beq .bad
 tst.w RT_CAPTURE_OWNER(a6)
 bne .bad
 tst.w RT_CLOCK+TC_ACTIVE(a6)
 bne .bad
 tst.w RT_HISTORY+TH_ACTIVE(a6)
 bne .bad
 tst.w RT_COMMANDS+CQ_ACTIVE(a6)
 bne .bad
 tst.w RT_SCHEDULER+TS_STATE(a6)
 bne .bad
 tst.l RT_EVENT(a6)
 bne .bad
 move.w RT_CLOCK+TC_RATE(a6),d0
 cmpi.w #50,d0
 beq .rate
 cmpi.w #60,d0
 bne .bad
.rate:
 ; Only fresh or completed states can cross a normal lifecycle epoch.
 move.w RT_CONSUMER+TF_PHASE(a6),d0
 beq .consumer
 cmpi.w #4,d0
 beq .consumer
 cmpi.w #6,d0
 bne .bad
.consumer:
 move.w RT_BODY+WB_PHASE(a6),d0
 beq .body
 cmpi.w #2,d0
 beq .body
 cmpi.w #3,d0
 bne .bad
.body:
 move.w RT_TARGET_PHASE(a6),d0
 beq .target
 cmpi.w #2,d0
 bne .bad
.target:
 move.w RT_GAUGE_PHASE(a6),d0
 beq .gauges
 cmpi.w #2,d0
 bne .bad
.gauges:
 move.w RT_MODAL+TM_PHASE(a6),d0
 beq .modal
 cmpi.w #4,d0
 beq .modal
 cmpi.w #5,d0
 bne .bad
.modal:
 move.w RT_BOUNDARY_PHASE(a6),d0
 beq .boundary
 cmpi.w #4,d0
 beq .boundary
 cmpi.w #5,d0
 bne .bad
.boundary:
 movea.l RT_HUNKS+24(a6),a5
 movea.l RT_HUNKS+20(a6),a0
 cmpa.l $60(a0),a5
 bne .bad
 lea $4c68(a5),a4
 move.l 22(a4),d3
 cmpi.l #10,d3
 bhi .bad
 adda.l #$3b88,a5
 tst.b $18(a5)
 bne .bad
 movea.l RT_HUNKS+8(a6),a0
 move.l $1c(a0),d4
 move.l RT_CAPTURE+24(a6),d5
 move.b $0f(a0),d6
 ext.w d6
 ext.l d6
 cmpi.l #-1,d6
 blt .bad
 cmpi.l #1,d6
 bgt .bad
 ; Preflight complete. No operation below rejects with stable bindings.
 add.l d3,RT_NATIVE_DISCARDED(a6)
 moveq #12,d0 ; eleven FIFO words plus its count longword
.clear_fifo:
 clr.w (a4)+
 dbf d0,.clear_fifo
 lea .reset_ranges(pc),a2
 moveq #(.reset_end-.reset_ranges)/4-1,d0
.range:
 move.w (a2)+,d1
 lea 0(a6,d1.w),a0
 move.w (a2)+,d1
 lsr.w #1,d1
 subq.w #1,d1
.clear:
 clr.w (a0)+
 dbf d1,.clear
 dbf d0,.range
 clr.w RT_BATCH(a6)
 clr.l RT_BOUNDARY_PHASE(a6)
 clr.l RT_BOUNDARY_RECORD(a6)
 clr.l RT_BOUNDARY_RECORD+4(a6)
 movea.l a6,a0
 bsr timing_runtime_gauges_seed
 lea RT_GUIDANCE_PRESENT(a6),a0
 bsr guidance_present_reset
 lea RT_MODE(a6),a0
 movea.l a5,a1
 bsr control_mode_init
 lea RT_SCHEDULER(a6),a0
 lea RT_ENDPOINT(a6),a1
 move.l d4,d0
 move.l d5,d1
 move.l d6,d2
 bsr timing_resume
 movea.l a6,a0
 bsr timing_runtime_actors_seed
 move.w #1,RT_CAPTURE_OWNER(a6)
 moveq #0,d0
 bra .done
.bad:
 moveq #-3,d0
.done:
 movem.l (sp)+,d1-d7/a0-a6
 rts
.reset_ranges:
 dc.w RT_PLAYER_READER+CP_SEQUENCE,CP_SIZE-CP_SEQUENCE
 dc.w RT_WORLD_READER+CW_SEQUENCE,CW_SIZE-CW_SEQUENCE
 dc.w RT_FIELD+SF_FIELD,SF_SIZE-SF_FIELD
 dc.w RT_START+SW_FIELD,SW_SIZE-SW_FIELD
 dc.w RT_IMPULSES+SI_FIELD,SI_SIZE-SI_FIELD
 dc.w RT_PLAYER+SE_FIELD,SE_SIZE-SE_FIELD
 dc.w RT_GEOMETRY+SGE_FIELD,SGE_SIZE-SGE_FIELD
 dc.w RT_BODY+WB_PHASE,2
 dc.w RT_TARGET_PHASE,6
 dc.w RT_GAUGE_PHASE,6
 dc.w RT_VIEW_PHASE,2
 dc.w RT_ACTOR_GENERATIONS,AG_SIZE
 dc.w RT_ACTOR_PRESENT+AC_VALID,2
 dc.w RT_RELEASE_PRESENT+AC_VALID,2
 dc.w RT_CONSUMER+TF_PHASE,TF_EFFECT-TF_PHASE
 dc.w RT_MODAL+TM_PHASE,2
 dc.w RT_FIRE,2
 dc.w RT_HEADING,2
 dc.w RT_PENDING,2
 dc.w RT_CAMERA,12
 dc.w RT_PACKET,PS_INPUT_SIZE
 dc.w RT_RECORD,TH_RECORD_SIZE
 dc.w RT_SAMPLE,TH_RECORD_SIZE
 dc.w RT_CAPTURE+28,12
.reset_end:

; Runtime script-modal hand-off after consumer result 3. Producer excluded.
; Return generic modal suspend status; relinquish FIFO ownership on success.
timing_runtime_modal_suspend:
 movem.l a0-a1,-(sp)
 movea.l a0,a1
 cmpi.w #5,RT_CONSUMER+TF_PHASE(a1)
 bne .bad
 lea RT_MODAL(a1),a0
 bsr timing_modal_suspend
 tst.l d0
 bne .done
 clr.w RT_CAPTURE_OWNER(a1)
 bra .done
.bad:
 moveq #-3,d0
.done:
 movem.l (sp)+,a0-a1
 rts

; a0=arena. Restore interrupts before calling: native interpreter waits for VBL.
; Complete the retained world once, then make the consumer's terminal state
; agree with the modal coordinator. Sampling/FIFO ownership remain native.
timing_runtime_modal_run:
 movem.l a0-a1,-(sp)
 movea.l a0,a1
 cmpi.w #5,RT_CONSUMER+TF_PHASE(a1)
 bne .bad
 tst.w RT_CAPTURE_OWNER(a1)
 bne .bad
 lea RT_MODAL(a1),a0
 bsr timing_modal_run
 tst.l d0
 beq .complete
 cmpi.l #3,d0
 beq .ended
 cmpi.l #-3,d0
 beq .done
 move.w #7,RT_CONSUMER+TF_PHASE(a1)
 bra .done
.complete:
 move.w #4,RT_CONSUMER+TF_PHASE(a1)
 bra .done
.ended:
 move.w #6,RT_CONSUMER+TF_PHASE(a1)
 bra .done
.bad:
 moveq #-3,d0
.done:
 movem.l (sp)+,a0-a1
 rts
