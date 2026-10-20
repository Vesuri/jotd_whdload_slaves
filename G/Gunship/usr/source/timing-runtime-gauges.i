; Private bar heights follow consumed fields, never render count.
; a0=arena, stable native bindings. Seed at preparation and normal activation.
; Lifecycle caller excludes producers/consumers. Preserve all registers.
timing_runtime_gauges_seed:
 movem.l d0/a0-a1,-(sp)
 movea.l RT_HUNKS+24(a0),a1
 moveq #0,d0
 tst.w $4bb0(a1)
 beq .slot
 moveq #1,d0
.slot:
 adda.w #$09bc,a1
 lea RT_GAUGES(a0),a0
 bsr gauge_field_init
 movem.l (sp)+,d0/a0-a1
 rts

; Once after field motion/map coordinates, before world visibility/weapons.
; a0=arena; return 0/-3, preserve others. No native writes. Caller faults on
; rejection; an applying stamp cannot be retried after partial publication.
timing_runtime_gauges:
 movem.l d1-d3/a0-a6,-(sp)
 movea.l a0,a6
 cmpi.l #1,RT_READY(a6)
 bne .bad
 tst.w RT_BOUNDARY_PHASE(a6)
 bne .retained
 cmpi.w #1,RT_CAPTURE_OWNER(a6)
 bne .bad
 bra .owned
.retained:
 cmpi.w #4,RT_BOUNDARY_PHASE(a6)
 bne .bad
 tst.w RT_CAPTURE_OWNER(a6)
 bne .bad
.owned:
 cmpi.w #3,RT_CONSUMER+TF_PHASE(a6)
 bne .bad
 ; Ordinary field completion leaves TS_STATE=0; a deadline leaves it at 2.
 move.w RT_SCHEDULER+TS_STATE(a6),d0
 beq .state
 cmpi.w #2,d0
 bne .bad
.state:
 move.l RT_CONSUMER+TF_FIELD(a6),d3
 cmp.l RT_RECORD+TR_FIELD(a6),d3
 bne .bad
 cmp.l RT_SCHEDULER+TS_FIELD(a6),d3
 bne .bad
 move.w RT_GAUGE_PHASE(a6),d0
 beq .new
 cmpi.w #2,d0
 bne .bad
 cmp.l RT_GAUGE_FIELD(a6),d3
 beq .bad
.new:
 cmpi.w #1,RT_GAUGES+GA_PHASE(a6)
 bhi .bad
 move.l d3,RT_GAUGE_FIELD(a6)
 move.w #1,RT_GAUGE_PHASE(a6)
 movea.l RT_HUNKS+24(a6),a5
 lea $157d(a5),a0
 lea RT_GAUGE_SCRATCH(a6),a1
 moveq #15,d1
.seed:
 move.b (a0)+,(a1)+
 dbf d1,.seed
 lea $3b88(a5),a0
 lea RT_GAUGE_SCRATCH(a6),a1
 lea RT_GAUGE_SCRATCH+16(a6),a2
 movea.l RT_HUNKS+16(a6),a3
 adda.w #$1c8,a3
 bsr presentation_build
 lea RT_GAUGES(a6),a0
 lea RT_GAUGE_SCRATCH(a6),a1
 lea $09bc(a5),a2
 bsr gauge_field_step
 move.w #2,RT_GAUGE_PHASE(a6)
 moveq #0,d0
 bra .done
.bad:
 moveq #-3,d0
.done:
 movem.l (sp)+,d1-d3/a0-a6
 rts

; a0=arena; draw latest private heights with the original painter. Caller
; serializes native foreground drawing/consumption. Return 0/-3, preserve
; other registers. Raw native targets (including externally owned holes)
; are restored after the draw. Physical bitmap caches remain painter-owned.
; Enter +ADC0 with the original displaced prefix's register values; works
; whether +ADB6 has been patched or not. No actual bitmap swap here.
timing_runtime_gauge_draw:
 movem.l d1-d7/a0-a6,-(sp)
 suba.w #12,sp ; native target pointer, then seven saved bytes + padding
 movea.l RT_HUNKS+24(a0),a1
 lea $157d(a1),a2
 move.l a2,(sp)
 lea 4(sp),a3
 moveq #6,d1
.save:
 move.b (a2)+,(a3)+
 dbf d1,.save
 movea.l RT_HUNKS(a0),a4
 adda.l #$adc0,a4
 adda.w #$09bc,a1
 lea RT_GAUGES(a0),a0
 movea.l (sp),a2
 bsr gauge_field_targets
 tst.l d0
 bne .done
 ; Native displaced +ADB6/+ADB8/+ADBA: D7=6, D4.w=0, A2=targets.
 moveq #6,d7
 clr.w d4
 jsr (a4)
 movea.l (sp),a2
 lea 4(sp),a3
 moveq #6,d1
.restore:
 move.b (a3)+,(a2)+
 dbf d1,.restore
 moveq #0,d0
.done:
 adda.w #12,sp
 movem.l (sp)+,d1-d7/a0-a6
 rts
