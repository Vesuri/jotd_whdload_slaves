; Foreground flight owner. Native installation is separate.
; a0=prepared arena with DRAW_READY, a1=enter exclusion, a2=leave exclusion.
; Both callbacks must preserve ALL registers including d0, balance nesting,
; and exclude input producers until leave. They may change CCR. Native UI,
; drawing, and field consumption run with normal interrupt delivery.
; Start only with normal inactive lifecycle admission. Return 4 flight ended,
; or a negative failure. Never resume pending effects or fall back to the old
; native tick after failure. Preserve non-result registers.
timing_runtime_loop:
 movem.l d1-d7/a0-a6,-(sp)
 movea.l a0,a6
 movea.l a1,a4
 movea.l a2,a5
 move.l a4,d0
 beq .bad
 move.l a5,d0
 beq .bad
 cmpi.l #1,RT_READY(a6)
 bne .bad
 cmpi.w #1,RT_DRAW_READY(a6)
 bne .bad
 jsr (a4)
 movea.l a6,a0
 bsr timing_runtime_activate
 jsr (a5)
 tst.l d0
 bne .done
.batch:
 movea.l a6,a0
 moveq #64,d0
 moveq #4,d1
 move.l #128,d2
 bsr timing_runtime_batch
 tst.l d0
 beq .draw
 cmpi.l #1,d0
 beq .batch
 cmpi.l #2,d0
 beq .boundary
 cmpi.l #3,d0
 beq .modal
 cmpi.l #4,d0
 beq .end
 cmpi.l #-2,d0
 beq .excess
 bra .fault
.draw:
 ; A drained snapshot need not mean the producer is caught up: fields can
 ; arrive during world work. Consume those before spending time on a frame.
 ; The producer only advances WRITE; a later arrival can wait for this draw.
 move.w RT_HISTORY+TH_READ(a6),d0
 cmp.w RT_HISTORY+TH_WRITE(a6),d0
 bne .batch
 movea.l a6,a0
 bsr timing_runtime_draw
 tst.l d0
 beq .batch
 bra .fault
.boundary:
 jsr (a4)
 movea.l a6,a0
 bsr timing_runtime_boundary_suspend
 jsr (a5)
 tst.l d0
 bne .fault
 movea.l a6,a0
 bsr timing_runtime_boundary_run
 tst.l d0
 beq .finish
 cmpi.l #4,d0
 bne .fault
.finish:
 movea.l a6,a0
 move.l #128,d0
 bsr timing_runtime_boundary_finish
 tst.l d0
 beq .activate
 cmpi.l #1,d0
 beq .finish
 cmpi.l #2,d0
 beq .boundary
 cmpi.l #3,d0
 beq .modal_run ; finish already suspended this retained world
 cmpi.l #4,d0
 beq .end
 bra .fault
.modal:
 jsr (a4)
 movea.l a6,a0
 bsr timing_runtime_modal_suspend
 jsr (a5)
 tst.l d0
 bne .fault
.modal_run:
 movea.l a6,a0
 bsr timing_runtime_modal_run
 tst.l d0
 beq .activate
 cmpi.l #3,d0
 beq .end
 bra .fault
.excess:
 ; Batch bounds stop before taking another field. Suspension accounts unread
 ; history; activation rebases clock/commands and invalidates predictions.
 ; A producer fault or unresolved phase is never classified as mere excess.
 jsr (a4)
 movea.l a6,a0
 bsr timing_runtime_suspend
 tst.l d0
 bne .excess_leave
 bsr timing_runtime_activate
.excess_leave:
 jsr (a5)
 tst.l d0
 beq .batch
 bra .fault
.activate:
 jsr (a4)
 movea.l a6,a0
 bsr timing_runtime_activate
 jsr (a5)
 tst.l d0
 beq .batch
 bra .fault
.end:
 jsr (a4)
 movea.l a6,a0
 bsr timing_runtime_suspend
 jsr (a5)
 tst.l d0
 bne .done
 moveq #4,d0
 bra .done
.fault:
 ; Stop producers while preserving the failed phase and original error.
 ; The caller reports/aborts; it must not continue the native world loop.
 move.l d0,d7
 jsr (a4)
 movea.l a6,a0
 bsr timing_runtime_suspend
 jsr (a5)
 move.l d7,d0
 bra .done
.bad:
 moveq #-3,d0
.done:
 movem.l (sp)+,d1-d7/a0-a6
 rts
