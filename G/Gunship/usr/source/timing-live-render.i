; Experimental native-render gameplay isolation, behind CUSTOM1.
; World effect construction already runs through the deadline-owned path.
; Field replay owns effect countdowns/animation during enhanced ownership.
; Only the admitted world visibility pass may collect/commit target state.
; a0=prepared arena, a2=resload. Return 0/-1, preserve other registers.
timing_render_install:
 movem.l d1-d2/a0-a3,-(sp)
 move.l _custom1(pc),d0
 beq .disabled
 cmpi.l #1,RT_READY(a0)
 bne .bad
 movea.l RT_HUNKS(a0),a1
 cmpi.w #$4eb9,$6356(a1)
 bne .bad
 cmpi.w #$4eb9,$63d4(a1)
 bne .bad
 movea.l a1,a3
 adda.l #$a450,a3
 cmpa.l $6358(a1),a3
 bne .bad
 cmpa.l $63d6(a1),a3
 bne .bad
 cmpi.w #$4eb9,$468c(a1)
 bne .bad
 movea.l a1,a3
 adda.l #$a58c,a3
 cmpa.l $468e(a1),a3
 bne .bad
 cmpi.w #$4eb9,$5c92(a1)
 bne .bad
 movea.l a1,a3
 adda.l #$9b9a,a3
 cmpa.l $5c94(a1),a3
 bne .bad
 cmpi.w #$4eb9,$5c98(a1)
 bne .bad
 movea.l a1,a0
 adda.l #$be5a,a0
 cmpa.l $5c9a(a1),a0
 bne .bad
 cmpi.w #$7405,(a0) ; following animation overwrites NZVC before use
 bne .bad
 lea timing_render_native_animation(pc),a0
 move.l a1,d1
 addi.l #$be5a,d1
 move.l d1,(a0)
 lea timing_render_native_effect(pc),a0
 move.l a3,(a0)
 lea timing_render_native_collect(pc),a0
 move.l a1,d1
 addi.l #$a450,d1
 move.l d1,(a0)
 lea timing_render_native_select(pc),a0
 move.l a1,d1
 addi.l #$a58c,d1
 move.l d1,(a0)
 lea .patches(pc),a0
 jsr resload_Patch(a2)
.disabled:
 moveq #0,d0
 bra .done
.bad:
 moveq #-1,d0
.done:
 movem.l (sp)+,d1-d2/a0-a3
 rts
.patches:
 PL_START
 PL_PS $5c92,timing_render_effect
 PL_PS $5c98,timing_render_animation
 PL_PS $6356,timing_render_collect
 PL_PS $63d4,timing_render_collect
 PL_PS $468c,timing_render_select
 PL_END

; Foreground/user-mode compatible on 68000: no privileged SR reads.
; Native ownership tail-calls the original constructor with unchanged regs/X.
; Its allocator overwrites NZVC before use. Enhanced ownership or retained UI
; returns without allocation/RNG/state writes; registers/X remain unchanged,
; other flags are unspecified (the following animation starts with MOVEQ).
timing_render_effect:
 move.l a0,-(sp)
 movea.l timing_runtime_arena(pc),a0
 tst.w RT_BOUNDARY_PHASE(a0)
 bne .skip
 cmpi.w #1,RT_CAPTURE_OWNER(a0)
 beq .skip
 movea.l (sp)+,a0
 move.l timing_render_native_effect(pc),-(sp)
 rts
.skip:
 movea.l (sp)+,a0
 rts
 even
timing_render_native_effect: dc.l 0

; Same ownership decision for the stateful animator. The next native call
; begins with BTST and does not consume the skipped animator's return flags.
timing_render_animation:
 move.l a0,-(sp)
 movea.l timing_runtime_arena(pc),a0
 tst.w RT_BOUNDARY_PHASE(a0)
 bne .skip
 cmpi.w #1,RT_CAPTURE_OWNER(a0)
 beq .skip
 movea.l (sp)+,a0
 move.l timing_render_native_animation(pc),-(sp)
 rts
.skip:
 movea.l (sp)+,a0
 rts
 even
timing_render_native_animation: dc.l 0

; The following native ADDQ overwrites collector flags; its loop reloads
; scratch registers. Permit collection only inside the admitted world pass.
timing_render_collect:
 move.l a0,-(sp)
 movea.l timing_runtime_arena(pc),a0
 tst.w RT_BOUNDARY_PHASE(a0)
 bne .retained
 cmpi.w #1,RT_CAPTURE_OWNER(a0)
 bne .native
 cmpi.w #1,RT_TARGET_PHASE(a0)
 bne .skip
 bra .native
.retained:
 cmpi.w #4,RT_BOUNDARY_PHASE(a0)
 bne .skip
 tst.w RT_CAPTURE_OWNER(a0)
 bne .skip
 cmpi.w #1,RT_TARGET_PHASE(a0)
 bne .skip
.native:
 movea.l (sp)+,a0
 move.l timing_render_native_collect(pc),-(sp)
 rts
.skip:
 movea.l (sp)+,a0
 rts

; Native panel selection is replaced by the world's private selector.
; The following TST overwrites NZVC; subsequent drawing reloads its inputs.
timing_render_select:
 move.l a0,-(sp)
 movea.l timing_runtime_arena(pc),a0
 tst.w RT_BOUNDARY_PHASE(a0)
 bne .skip
 cmpi.w #1,RT_CAPTURE_OWNER(a0)
 beq .skip
 movea.l (sp)+,a0
 move.l timing_render_native_select(pc),-(sp)
 rts
.skip:
 movea.l (sp)+,a0
 rts
 even
timing_render_native_collect: dc.l 0
timing_render_native_select: dc.l 0
