; Presentation-only heading reads. Never borrow the authoritative player byte.
; a0=arena,a2=resload. Validate all three original loads before patching.
timing_script_heading_install:
 movem.l d1/a0-a4,-(sp)
 move.l _custom1(pc),d0
 beq .disabled
 cmpi.l #1,RT_READY(a0)
 bne .bad
 movea.l RT_HUNKS(a0),a1
 movea.l RT_HUNKS+24(a0),a3
 adda.w #$3ce3,a3
 cmpi.w #$1239,$5d20(a1)
 bne .bad
 cmpa.l $5d22(a1),a3
 bne .bad
 cmpi.w #$1439,$68a2(a1)
 bne .bad
 cmpa.l $68a4(a1),a3
 bne .bad
 cmpi.w #$1439,$68d2(a1)
 bne .bad
 cmpa.l $68d4(a1),a3
 bne .bad
 lea timing_script_heading_native(pc),a4
 move.l a3,(a4)
 lea .patches(pc),a0
 jsr resload_Patch(a2)
.disabled:
 moveq #0,d0
 bra .done
.bad:
 moveq #-1,d0
.done:
 movem.l (sp)+,d1/a0-a4
 rts
.patches:
 PL_START
 PL_PS $5d20,timing_script_heading_d1
 PL_PS $68a2,timing_script_heading_d2
 PL_PS $68d2,timing_script_heading_d2
 PL_END

; Exactly the native byte-load ABI: preserve upper destination bits, other
; registers and X. Final MOVE establishes native NZVC after admission tests.
timing_script_heading_d1:
 move.l a0,-(sp)
 movea.l timing_runtime_arena(pc),a0
 cmpi.l #1,RT_READY(a0)
 bne .native
 cmpi.w #1,RT_CAPTURE_OWNER(a0)
 bne .native
 tst.w RT_BOUNDARY_PHASE(a0)
 bne .native
 cmpi.w #1,RT_TARGET_PHASE(a0)
 beq .native
 cmpi.w #1,RT_VIEW_PHASE(a0)
 bne .native
 lea RT_SCRIPT_POSE+6(a0),a0
 bra .load
.native:
 movea.l timing_script_heading_native(pc),a0
.load:
 move.b (a0),d1
 movea.l (sp)+,a0
 rts

; Exactly the native byte-load ABI: preserve upper destination bits, other
; registers and X. Final MOVE establishes native NZVC after admission tests.
timing_script_heading_d2:
 move.l a0,-(sp)
 movea.l timing_runtime_arena(pc),a0
 cmpi.l #1,RT_READY(a0)
 bne .native
 cmpi.w #1,RT_CAPTURE_OWNER(a0)
 bne .native
 tst.w RT_BOUNDARY_PHASE(a0)
 bne .native
 cmpi.w #1,RT_TARGET_PHASE(a0)
 beq .native
 cmpi.w #1,RT_VIEW_PHASE(a0)
 bne .native
 lea RT_SCRIPT_POSE+6(a0),a0
 bra .load
.native:
 movea.l timing_script_heading_native(pc),a0
.load:
 move.b (a0),d2
 movea.l (sp)+,a0
 rts
 even
timing_script_heading_native: dc.l 0
