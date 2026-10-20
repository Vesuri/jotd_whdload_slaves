; Install only with CUSTOM1 and prepared runtime. Preserve native call targets
; for ordinary ownership; copied panel code is unnecessary.
; a0=arena,a2=resload; return 0/-1, preserve others.
timing_target_view_install:
 movem.l a0-a3,-(sp)
 move.l _custom1(pc),d0
 beq .disabled
 cmpi.l #1,RT_READY(a0)
 bne .bad
 movea.l RT_HUNKS(a0),a1
 cmpi.w #$4eb9,$5c78(a1)
 bne .bad
 lea $468c(a1),a3
 cmpa.l $5c7a(a1),a3
 bne .bad
 cmpi.w #$4eb9,$46a4(a1)
 bne .bad
 movea.l a1,a0
 adda.l #$a6e4,a0
 cmpa.l $46a6(a1),a0
 bne .bad
 lea timing_view_native_draw(pc),a3
 move.l a0,(a3)
 lea $468c(a1),a0
 lea timing_view_native_panel(pc),a3
 move.l a0,(a3)
 lea .patches(pc),a0
 jsr resload_Patch(a2)
.disabled:
 moveq #0,d0
 bra .done
.bad:
 moveq #-1,d0
.done:
 movem.l (sp)+,a0-a3
 rts
.patches:
 PL_START
 PL_PS $5c78,timing_view_panel
 PL_PS $46a4,timing_view_draw
 PL_END

timing_view_panel:
 movem.l d0/a0,-(sp)
 movea.l timing_runtime_arena(pc),a0
 tst.w RT_BOUNDARY_PHASE(a0)
 bne .native
 cmpi.w #1,RT_CAPTURE_OWNER(a0)
 bne .native
 cmpi.w #1,RT_VIEW_PHASE(a0)
 bne .skip
 bsr timing_runtime_target_panel
.skip:
 movem.l (sp)+,d0/a0
 rts
.native:
 movem.l (sp)+,d0/a0
 move.l timing_view_native_panel(pc),-(sp)
 rts

; +46AA refreshes sprites after this call, reloading its own inputs. No stale
; selected-target drawing outside an active private panel projection.
timing_view_draw:
 move.l a0,-(sp)
 movea.l timing_runtime_arena(pc),a0
 tst.w RT_BOUNDARY_PHASE(a0)
 bne .skip
 cmpi.w #1,RT_CAPTURE_OWNER(a0)
 bne .native
 cmpi.w #2,RT_VIEW_PHASE(a0)
 bne .skip
 tst.w RT_VIEW+TPV_VALID(a0)
 beq .skip
.native:
 movea.l (sp)+,a0
 move.l timing_view_native_draw(pc),-(sp)
 rts
.skip:
 movea.l (sp)+,a0
 rts
 even
timing_view_native_panel: dc.l 0
timing_view_native_draw: dc.l 0
