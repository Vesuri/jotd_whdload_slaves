; Separate map coordinate refresh from per-buffer drawing. CUSTOM1/runtime only.
; a0=arena, a2=resload, return 0/-1 and preserve other registers.
timing_map_install:
 movem.l d1-d3/a0-a4,-(sp)
 move.l _custom1(pc),d0
 beq .disabled
 cmpi.l #1,RT_READY(a0)
 bne .bad
 movea.l RT_HUNKS(a0),a1
 movea.l RT_HUNKS+20(a0),a3
 lea $48(a3),a3
 cmpi.w #$5279,$489a(a1)
 bne .bad
 cmpa.l $489c(a1),a3
 bne .bad
 cmpi.w #$3039,$48a0(a1)
 bne .bad
 cmpa.l $48a2(a1),a3
 bne .bad
 cmpi.l #$0c400008,$48a6(a1)
 bne .bad
 cmpi.l #$64046100,$48aa(a1)
 bne .bad
 cmpi.w #$feac,$48ae(a1)
 bne .bad
 cmpi.w #$4eb9,$48b0(a1)
 bne .bad
 lea $44dc(a1),a3
 cmpa.l $48b2(a1),a3
 bne .bad
 lea timing_map_native_sprite(pc),a4
 move.l a3,(a4)
 lea $475a(a1),a3
 lea timing_map_native_coordinates(pc),a4
 move.l a3,(a4)
 lea $489a(a1),a3
 lea timing_map_native_prefix(pc),a4
 moveq #13,d1
.copy:
 move.w (a3)+,(a4)+
 dbf d1,.copy
 move.w #$4e75,(a4)
 lea timing_map_native_prefix(pc),a4
 lea timing_map_coordinates_call(pc),a3
 suba.l a4,a3
 move.l a3,d1
 subi.w #20,d1
 move.w d1,20(a4)
 lea .patches(pc),a0
 jsr resload_Patch(a2)
.disabled:
 moveq #0,d0
 bra .done
.bad:
 moveq #-1,d0
.done:
 movem.l (sp)+,d1-d3/a0-a4
 rts
.patches:
 PL_START
 PL_PSS $489a,timing_map_frame,22
 PL_END

timing_map_frame:
 move.l a0,-(sp)
 movea.l timing_runtime_arena(pc),a0
 tst.w RT_BOUNDARY_PHASE(a0)
 bne .draw
 cmpi.w #1,RT_CAPTURE_OWNER(a0)
 beq .draw
 movea.l (sp)+,a0
 bra timing_map_native_prefix
.draw:
 movea.l (sp)+,a0
 move.l timing_map_native_sprite(pc),-(sp)
 rts

timing_map_coordinates_call:
 move.l timing_map_native_coordinates(pc),-(sp)
 rts
 even
timing_map_native_prefix: ds.b 30
timing_map_native_coordinates: dc.l 0
timing_map_native_sprite: dc.l 0
