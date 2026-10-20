; CUSTOM1-only allocation identity tracking. All three native constructor
; callers use this allocator, including calls retained by runtime clones.
; a0=arena,a2=resload; return 0/-1, preserve other registers.
timing_actor_generation_install:
 movem.l d1-d2/a0-a4,-(sp)
 move.l _custom1(pc),d0
 beq .disabled
 cmpi.l #1,RT_READY(a0)
 bne .bad
 movea.l RT_HUNKS(a0),a1
 movea.l a1,a3
 adda.l #$ba08,a3
 adda.l #$bea8,a1
 cmpa.l 4(a1),a3
 bne .bad
 cmpa.l 16(a1),a3
 bne .bad
 addq.l #2,a3
 cmpa.l 28(a1),a3
 bne .bad
 cmpa.l 36(a1),a3
 bne .bad
 lea .signature(pc),a4
 moveq #13,d2
.check:
 move.w (a4)+,d1
 move.w 0(a1,d1.w),d0
 cmp.w (a4)+,d0
 bne .bad
 dbf d2,.check
 movea.l a1,a3
 lea timing_actor_native_allocator(pc),a0
 moveq #21,d1
.copy:
 move.w (a3)+,(a0)+
 dbf d1,.copy
 suba.l #$bea8,a1
 lea .patches(pc),a0
 jsr resload_Patch(a2)
.disabled:
 moveq #0,d0
 bra .done
.bad:
 moveq #-1,d0
.done:
 movem.l (sp)+,d1-d2/a0-a4
 rts
.signature:
 dc.w 0,$7005,2,$3239,8,$01c1,10,$57c8,12,$fffc,14,$33c1
 dc.w 20,$4a40,22,$6700,24,$0010,26,$3239,32,$01c1,34,$33c1
 dc.w 40,$5240,42,$4e75
.patches:
 PL_START
 PL_P $bea8,timing_actor_allocate
 PL_END

timing_actor_allocate:
 move.l a0,-(sp)
 movea.l timing_runtime_arena(pc),a0
 tst.w RT_BOUNDARY_PHASE(a0)
 bne .retained
 cmpi.w #1,RT_CAPTURE_OWNER(a0)
 beq .tracked
 bra .native
.retained:
 cmpi.w #4,RT_BOUNDARY_PHASE(a0)
 bne .native
 tst.w RT_CAPTURE_OWNER(a0)
 bne .native
.tracked:
 bsr timing_actor_native_allocator
 lea RT_ACTOR_GENERATIONS(a0),a0
 bsr actor_generation_record
 movea.l (sp)+,a0
 ; Replay the native final ADDQ exactly, including X/C on full failure.
 ; No privileged SR/CCR access; compatible with user-mode 68000 and 68060.
 subq.w #1,d0
 addq.w #1,d0
 rts
.native:
 movea.l (sp)+,a0
 bra timing_actor_native_allocator
 even
timing_actor_native_allocator: ds.b 44
