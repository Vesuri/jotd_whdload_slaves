; CUSTOM1-only identity/discontinuity stamp for native split-object slot 5.
; All stores through 7BD0 are stamped, including ordinary world motion. The
; cache captures after the entire world step, so it observes the final stamp.
; Private preview A5 records never advance the authoritative generation.
; Uses slot zero of a separate AG_SIZE record, including saturating exhaustion.
; a0=arena,a2=resload; return 0/-1, preserve other registers.
timing_script_generation_install:
 movem.l d1-d2/a0-a4,-(sp)
 move.l _custom1(pc),d0
 beq .disabled
 cmpi.l #1,RT_READY(a0)
 bne .bad
 movea.l RT_HUNKS(a0),a1
 lea $7bd0(a1),a3
 lea timing_script_native_store(pc),a4
 moveq #(timing_script_native_store_end-timing_script_native_store)/2-1,d2
.check:
 move.w (a3)+,d0
 cmp.w (a4)+,d0
 bne .bad
 dbf d2,.check
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
.patches:
 PL_START
 PL_P $7bd0,timing_script_store
 PL_END

timing_script_store:
 movem.l d0-d2/a0-a1,-(sp)
 cmpi.b #5,d0 ; native ANDI.L uses only the original low byte
 bne .native
 movea.l timing_runtime_arena(pc),a0
 cmpi.l #1,RT_READY(a0)
 bne .native
 movea.l RT_HUNKS+24(a0),a1
 adda.w #$3b88,a1
 cmpa.l a1,a5
 bne .native
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
 ; Native ANDI/MOVE/CMP establish NZVC but preserve incoming X. Capture X
 ; without reading privileged SR or using a post-68000 CCR instruction.
 moveq #0,d1
 roxl.b #1,d1
 move.l d1,-(sp)
 lea RT_SCRIPT_GENERATION(a0),a0
 moveq #1,d0
 bsr actor_generation_record
 move.l (sp)+,d1
 lsr.b #1,d1 ; restore original X; the native prefix replaces NZVC below
.native:
 movem.l (sp)+,d0-d2/a0-a1
 bra timing_script_native_store

; Byte-exact 74-byte native store. The installer verifies the entire original.
; No absolute operands; A5 remains either native P or the caller's private P.
timing_script_native_store:
 andi.l #$ff,d0
 movea.l a5,a0
 adda.l d0,a0
 move.b $1e(a5),$56(a0)
 move.b $20(a5),$d6(a0)
 move.b $4c(a5),$1d6(a0)
 move.b $4d(a5),$256(a0)
 cmpi.b #6,d0
 bcc.w .done
 move.b $1f(a5),$d0(a0)
 move.b $21(a5),$150(a0)
 move.b $22(a5),$250(a0)
 move.b $23(a5),$1d0(a0)
 move.b $4b(a5),$156(a0)
.done:
 rts
timing_script_native_store_end:
