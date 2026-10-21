; CUSTOM1-only gauge painter ownership. Native behavior until activation.
; a0=arena, a2=resload; return 0/-1, preserve other registers.
timing_gauges_install:
 movem.l d1/a0-a3,-(sp)
 move.l _custom1(pc),d0
 beq .disabled
 cmpi.l #1,RT_READY(a0)
 bne .bad
 movea.l RT_HUNKS(a0),a1
 adda.l #$adb6,a1
 cmpi.l #$7e064244,0(a1)
 bne .bad
 cmpi.w #$45f9,4(a1)
 bne .bad
 movea.l RT_HUNKS+24(a0),a3
 adda.w #$157d,a3
 cmpa.l 6(a1),a3
 bne .bad
 cmpi.w #$47f9,10(a1)
 bne .bad
 movea.l RT_HUNKS+24(a0),a3
 adda.w #$09bc,a3
 cmpa.l 12(a1),a3
 bne .bad
 ; Keep the exact ten displaced bytes, followed by an absolute continuation.
 lea timing_gauges_native(pc),a0
 lea 0(a1),a3
 moveq #4,d1
.copy:
 move.w (a3)+,(a0)+
 dbf d1,.copy
 move.w #$4ef9,(a0)+
 move.l a3,(a0)
 suba.l #$adb6,a1
 lea .patches(pc),a0
 jsr resload_Patch(a2)
.disabled:
 moveq #0,d0
 bra .done
.bad:
 moveq #-1,d0
.done:
 movem.l (sp)+,d1/a0-a3
 rts
.patches:
 PL_START
 PL_P $adb6,timing_render_gauges
 PL_END

timing_render_gauges:
 movem.l d0/a0,-(sp)
 movea.l timing_runtime_arena(pc),a0
 tst.w RT_BOUNDARY_PHASE(a0)
 bne .draw
 cmpi.w #1,RT_CAPTURE_OWNER(a0)
 beq .draw
 movem.l (sp)+,d0/a0
 bra timing_gauges_native
.draw:
 ; The timing core may exceed a 68000 signed-word call displacement.
 move.l a1,-(sp)
.gauge_call:
 lea .gauge_call(pc),a1
 adda.l #timing_runtime_gauge_draw-.gauge_call,a1
 jsr (a1)
 movea.l (sp)+,a1
 movem.l (sp)+,d0/a0
 rts
 even
timing_gauges_native: ds.b 16
