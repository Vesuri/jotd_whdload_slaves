; Runtime ownership of native gameplay VBL state, experimental builds only.
; Cosmetic RNG/audio/counters/drawing outside these sites stay native.
; Guidance display reconstruction is separate from its extracted state update.
; A retained UI boundary freezes gameplay even while keyboard ownership is native.
; a0=prepared arena, a2=resload. Validate every site before changing any.
; Return 0/-1, preserving other registers. CUSTOM1 is the master gate.
timing_vbl_install:
 movem.l d1-d7/a0-a6,-(sp)
 move.l _custom1(pc),d0
 beq .disabled
 cmpi.l #1,RT_READY(a0)
 bne .bad
 movea.l RT_HUNKS(a0),a1
 movea.l RT_HUNKS+24(a0),a3
 cmpi.w #$5339,$4ba8(a1)
 bne .bad
 lea $4296(a3),a4
 cmpa.l $4baa(a1),a4
 bne .bad
 cmpi.w #$5339,$4bba(a1)
 bne .bad
 lea $42f6(a3),a4
 cmpa.l $4bbc(a1),a4
 bne .bad
 cmpi.w #$5339,$4c32(a1)
 bne .bad
 lea $42f7(a3),a4
 cmpa.l $4c34(a1),a4
 bne .bad
 cmpi.w #$4eb9,$4c12(a1)
 bne .bad
 movea.l a1,a4
 adda.l #$a1c8,a4
 cmpa.l $4c14(a1),a4
 bne .bad
 ; All six effect countdown stores form one indivisible hook span.
 lea $4c40(a1),a5
 movea.l a1,a6
 adda.l #$c724,a6
 moveq #5,d1
.effect_check:
 cmpi.w #$9139,(a5)+
 bne .bad
 cmpa.l (a5)+,a6
 bne .bad
 addq.l #1,a6
 dbf d1,.effect_check
 lea timing_vbl_native_guidance(pc),a3
 move.l a4,(a3)
 lea .patches(pc),a0
 jsr resload_Patch(a2)
.disabled:
 moveq #0,d0
 bra .done
.bad:
 moveq #-1,d0
.done:
 movem.l (sp)+,d1-d7/a0-a6
 rts
.patches:
 PL_START
 PL_PS $4ba8,timing_vbl_timer_weapon
 PL_PS $4bba,timing_vbl_timer_ground
 PL_PS $4c32,timing_vbl_timer_hit
 PL_PS $4c12,timing_vbl_guidance
 PL_PSS $4c40,timing_vbl_effect_timers,30
 PL_END

; Interrupt-only entries: MOVE SR is legal in the native VBL server.
; Return exactly the native SUBQ.B flags even when suppressing its store.
; Native zero guards remain before each site; no saturation is added here.
; Historical label: +4296 is hit flash/audio response, not weapon reload.
timing_vbl_timer_weapon:
 move.w sr,-(sp)
 movem.l d0/a0-a1,-(sp)
 move.w #$4296,d0
 bra timing_vbl_timer_common
timing_vbl_timer_ground:
 move.w sr,-(sp)
 movem.l d0/a0-a1,-(sp)
 move.w #$42f6,d0
 bra timing_vbl_timer_common
timing_vbl_timer_hit:
 move.w sr,-(sp)
 movem.l d0/a0-a1,-(sp)
 move.w #$42f7,d0
timing_vbl_timer_common:
 movea.l timing_runtime_arena(pc),a0
 movea.l RT_HUNKS+24(a0),a1
 adda.w d0,a1
 tst.w RT_BOUNDARY_PHASE(a0)
 bne .suppressed
 cmpi.w #1,RT_CAPTURE_OWNER(a0)
 bne .native
.suppressed:
 move.b (a1),d0
 subq.b #1,d0
 bra .flags
.native:
 subq.b #1,(a1)
.flags:
 move.w sr,12(sp)
 movem.l (sp)+,d0/a0-a1
 move.w (sp)+,ccr
 rts

; Native ownership tail-calls the original routine with unchanged inputs.
; Runtime ownership returns without guidance state/display side effects.
timing_vbl_guidance:
 subq.l #4,sp
 move.w sr,-(sp)
 move.l a0,-(sp)
 movea.l timing_runtime_arena(pc),a0
 tst.w RT_BOUNDARY_PHASE(a0)
 bne .runtime
 cmpi.w #1,RT_CAPTURE_OWNER(a0)
 beq .runtime
 move.l timing_vbl_native_guidance(pc),6(sp)
 movea.l (sp)+,a0
 move.w (sp)+,ccr
 rts
.runtime:
 movea.l (sp)+,a0
 move.w (sp)+,ccr
 addq.l #4,sp
 rts
 even
timing_vbl_native_guidance: dc.l 0

; Replace six native SUB.B D0,abs stores. D0 is still native (normally 1).
; Preserve every register and the exact final subtraction flags in all modes.
timing_vbl_effect_timers:
 move.w sr,-(sp)
 movem.l d1-d2/a0-a1,-(sp)
 movea.l timing_runtime_arena(pc),a0
 movea.l RT_HUNKS(a0),a1
 adda.l #$c724,a1
 tst.w RT_BOUNDARY_PHASE(a0)
 bne .suppressed
 cmpi.w #1,RT_CAPTURE_OWNER(a0)
 beq .suppressed
 moveq #5,d2
.native:
 sub.b d0,(a1)+
 dbf d2,.native
 bra .flags
.suppressed:
 move.b 5(a1),d1
 sub.b d0,d1
.flags:
 move.w sr,16(sp)
 movem.l (sp)+,d1-d2/a0-a1
 move.w (sp)+,ccr
 rts
