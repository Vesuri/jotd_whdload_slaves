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
