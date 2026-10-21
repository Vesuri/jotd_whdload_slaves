; Renderer-only six-slot forward prediction. Capture only after a serialized
; completed world step, lifecycle seed, or certified guided release.
; Lifecycle owners clear AC_VALID before reusing generation zero.
AC_PREVIEW equ 0
AC_TICK equ 4
AC_PHASE equ 8 ; capture phase: world remainder or guided-release field
AC_VALID equ 10
AC_GENERATIONS equ 12 ; six longs plus exhaustion word
AC_MASKS equ AC_GENERATIONS+AG_SIZE ; allocation and eligibility words
AC_CURRENT equ AC_MASKS+4 ; four six-word coordinate/vertical arrays
AC_BYTES equ AC_CURRENT+48 ; fifteen six-byte actor arrays
AC_NEXT equ AC_BYTES+90 ; three six-word predicted coordinate arrays
AC_SAFE equ AC_NEXT+36
AC_SELECTED equ AC_SAFE+2 ; selector dependency for native bit-7 homing actors
AC_SIZE equ AC_SELECTED+12

; a0=AC,a1=prepared AP,a2=AG,a3=committed P,d0=tick,d1=phase0..59 (caller requires phase < field rate).
; Return 0/-3, preserve others. Invalid phase writes nothing. Caller flushes
; AP code after preparation and excludes all actor/identity writers.
actor_present_capture:
 movem.l d1-d7/a0-a6,-(sp)
 cmpi.l #59,d1
 bhi .bad
 movea.l a0,a6
 move.l a1,AC_PREVIEW(a6)
 move.l d0,AC_TICK(a6)
 move.w d1,AC_PHASE(a6)
 clr.w AC_VALID(a6)
 lea AC_GENERATIONS(a6),a0
 moveq #AG_SIZE/2-1,d2
.generations:
 move.w (a2)+,(a0)+
 dbf d2,.generations
 movea.l AP_H0(a1),a2
 adda.l #$ba08,a2
 move.w (a2),AC_MASKS(a6)
 move.w 4(a2),AC_MASKS+2(a6)
 adda.w #$c6a0-$ba08,a2
 lea AC_CURRENT(a6),a0
 moveq #(48+90)/2-1,d2
.current:
 move.w (a2)+,(a0)+
 dbf d2,.current
 movea.l a1,a0
 movea.l a3,a1
 bsr actor_preview_step
 move.w d0,AC_SAFE(a6)
 movea.l AC_PREVIEW(a6),a0
 move.l AP_SELECTED(a0),AC_SELECTED(a6)
 move.l AP_SELECTED+4(a0),AC_SELECTED+4(a6)
 move.l AP_SELECTED+8(a0),AC_SELECTED+8(a6)
 lea AP_ACTORS(a0),a0
 lea AC_NEXT(a6),a1
 moveq #17,d2
.next:
 move.w (a0)+,(a1)+
 dbf d2,.next
 move.w #1,AC_VALID(a6)
 moveq #0,d0
 bra .done
.bad:
 moveq #-3,d0
.done:
 movem.l (sp)+,d1-d7/a0-a6
 rts

; a0=AC,a1=current AG,a2=private 36-byte output,d0=current tick,
; d1=current clock phase,d2=50/60 field rate. Return predicted-slot mask;
; -3 invalid clock input writes nothing. AC must have a prepared AP binding.
; Always seed output from committed coordinates; stale/changed slots snap to
; these. No cached prediction survives its tick, generation, or discontinuity.
; The fraction is elapsed fields / fields to the next deadline (17/17/16 PAL,
; 20 NTSC), measured FROM the completed tick, never one tick behind.
actor_present_build:
 movem.l d1-d7/a0-a6,-(sp)
 clr.l -(sp)
 clr.l -(sp)
 bra actor_present_build_common

; Same clock/capture/identity contract, plus a3=36 certified endpoint bytes
; and d3=safe-slot mask from a freshly evaluated selector-fed actor preview.
; Caller owns selector/impulse agreement and serialized immutable inputs.
; Bypass ONLY the old captured-selector equality test: the new endpoint
; already uses the forecast selector. All other discontinuity checks remain.
; No AC or endpoint writes. Reject invalid masks before touching output.
actor_present_build_forecast:
 cmpa.w #0,a3
 beq .bad_mask
 cmpi.l #63,d3
 bhi .bad_mask
 movem.l d1-d7/a0-a6,-(sp)
 move.l d3,-(sp)
 move.l a3,-(sp)
 bra actor_present_build_common
.bad_mask:
 moveq #-3,d0
 rts

actor_present_build_common:
 cmpi.l #50,d2
 beq .rate
 cmpi.l #60,d2
 bne .bad
.rate:
 cmp.l d2,d1
 bhs .bad
 movea.l a0,a6
 movea.l a1,a5
 movea.l a2,a4
 movea.l AC_PREVIEW(a6),a0
 movea.l AP_H0(a0),a3
 adda.l #$c6a0,a3
 movea.l a3,a0
 moveq #17,d3
.seed:
 move.w (a0)+,(a2)+
 dbf d3,.seed
 moveq #0,d7
 cmpi.w #1,AC_VALID(a6)
 bne .result
 cmp.l AC_TICK(a6),d0
 bne .result
 sub.w AC_PHASE(a6),d1
 bmi .result
 ; Divide by three after removing the deadline remainder. This deliberately
 ; refuses an inconsistent clock phase rather than inventing elapsed fields.
 move.l d1,d3
 divu.w #3,d3
 move.l d3,d4
 swap d4
 tst.w d4
 bne .result
 andi.l #$ffff,d3 ; elapsed fields
 sub.w AC_PHASE(a6),d2
 addq.w #2,d2
 divu.w #3,d2
 andi.l #$ffff,d2 ; interval length
 move.w AC_SAFE(a6),d7
 tst.l (sp)
 beq .mask_ready
 move.w 6(sp),d7
.mask_ready:
 movea.l AC_PREVIEW(a6),a0
 movea.l AP_H0(a0),a0
 adda.l #$ba08,a0
 and.w (a0),d7
 and.w 4(a0),d7
 and.w AC_MASKS(a6),d7
 and.w AC_MASKS+2(a6),d7
 move.w AG_EXHAUSTED(a5),d0
 or.w AC_GENERATIONS+AG_EXHAUSTED(a6),d0
 not.w d0
 and.w d0,d7
 moveq #5,d6
.slot:
 btst d6,d7
 beq .next_slot
 move.w d6,d5
 lsl.w #2,d5
 move.l 0(a5,d5.w),d0
 cmp.l AC_GENERATIONS(a6,d5.w),d0
 bne .reject
 tst.l (sp)
 bne .selector_ready
 ; Native bit-7 steering reads AA0A..AA15 unless bit-3/4 modes win first.
 ; A different selector invalidates only dependent homing slots. Capture
 ; it in AC, not the shared AP workspace reused by guided-release previews.
 move.b 54(a3,d6.w),d0
 andi.b #$98,d0
 cmpi.b #$80,d0
 bne .selector_ready
 movea.l AC_PREVIEW(a6),a0
 movea.l AP_H0(a0),a0
 adda.l #$aa0a,a0
 lea AC_SELECTED(a6),a1
 REPT 3
 cmpm.l (a0)+,(a1)+
 bne .reject
 ENDR
.selector_ready:
 ; Certify current coordinates and vertical state against the captured pose.
 move.w d6,d5
 add.w d5,d5
 lea 0(a3,d5.w),a0
 lea AC_CURRENT(a6,d5.w),a1
 moveq #3,d4
.coords:
 move.w (a0),d0
 cmp.w (a1),d0
 bne .reject
 adda.w #12,a0
 adda.w #12,a1
 dbf d4,.coords
 ; Effect frame (array 2) and field countdown (array 14) do not change
 ; free flight. All other actor bytes, including type/lifetime/guidance,
 ; must match. Impact changes type as well as restarting the countdown.
 lea 48(a3,d6.w),a0
 lea AC_BYTES(a6,d6.w),a1
 moveq #14,d4
.bytes:
 tst.w d4
 beq .animation
 cmpi.w #12,d4
 beq .animation
 move.b (a0),d0
 cmp.b (a1),d0
 bne .reject
.animation:
 addq.w #6,a0
 addq.w #6,a1
 dbf d4,.bytes
 lea AC_CURRENT(a6,d5.w),a0
 lea AC_NEXT(a6),a1
 tst.l (sp)
 beq .endpoint_ready
 movea.l (sp),a1
.endpoint_ready:
 adda.w d5,a1
 lea 0(a4,d5.w),a2
 moveq #2,d4
.axis:
 move.w (a1),d0
 sub.w (a0),d0 ; shortest native wrapped-word delta
 muls.w d3,d0
 divs.w d2,d0
 move.l d0,d1
 swap d1
 tst.w d1
 bpl .rounded
 subq.w #1,d0 ; floor negative non-integral displacement
.rounded:
 add.w (a0),d0
 move.w d0,(a2)
 adda.w #12,a0
 adda.w #12,a1
 adda.w #12,a2
 dbf d4,.axis
 bra .next_slot
.reject:
 bclr d6,d7
.next_slot:
 dbf d6,.slot
.result:
 moveq #0,d0
 move.w d7,d0
 bra .done
.bad:
 moveq #-3,d0
.done:
 addq.l #8,sp
 movem.l (sp)+,d1-d7/a0-a6
 rts
