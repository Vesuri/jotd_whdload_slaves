; Field-clocked bar-gauge animation, independent of actual bitmap swaps.
; Reference: native +adb6..+ae3a drawn once per field, alternating buffers.
; Seven descriptors are 12 bytes each; +6 is scale, +8/+9 bitmap positions.
; Private virtual positions advance one alternating slot per consumed field.
; The renderer retains its own bitmap caches and catches up by drawing.
GA_PHASE equ 0 ; virtual slot to advance next, 0/1
GA_VALUES equ 2 ; seven pairs of byte heights
GA_SIZE equ 16

; a0=private state, a1=native descriptors, d0=first virtual slot (0/1).
; Return 0/-3, preserve others. Reject invalid phase before any state write.
gauge_field_init:
 cmpi.l #1,d0
 bhi .bad
 movem.l d1/a0-a1,-(sp)
 move.w d0,(a0)+
 moveq #6,d1
.copy:
 move.b 8(a1),(a0)+
 move.b 9(a1),(a0)+
 adda.w #12,a1
 dbf d1,.copy
 movem.l (sp)+,d1/a0-a1
 moveq #0,d0
 rts
.bad:
 moveq #-3,d0
 rts

; a0=state, a1=seven current native target bytes, a2=descriptors.
; Return 0/-3; preserve others. Only state/stack writes; no hardware access.
; Bit 7 retains native immediate fill. Otherwise advance one signed-byte
; comparison step, exactly as the native routine advances that buffer slot.
gauge_field_step:
 movem.l d1-d5/a0-a3,-(sp)
 move.w GA_PHASE(a0),d0
 cmpi.w #1,d0
 bhi .bad
 lea GA_VALUES(a0),a3
 adda.w d0,a3
 moveq #6,d5
.gauge:
 moveq #0,d1
 move.b (a1)+,d1
 move.w d1,d2
 andi.w #31,d2
 mulu.w 6(a2),d2
 lsr.w #5,d2
 tst.b d1
 bmi .store
 move.b (a3),d3
 cmp.b d3,d2
 beq .next
 blt .down
 addq.b #1,d3
 bra .slow
.down:
 subq.b #1,d3
.slow:
 move.b d3,d2
.store:
 move.b d2,(a3)
.next:
 addq.l #2,a3
 adda.w #12,a2
 dbf d5,.gauge
 eori.w #1,GA_PHASE(a0)
 moveq #0,d0
 bra .done
.bad:
 moveq #-3,d0
.done:
 movem.l (sp)+,d1-d5/a0-a3
 rts

; a0=state, a1=descriptors, a2=seven-byte render-target destination.
; Encode the latest virtual slot as native target codes with immediate-fill
; bit set. This makes +adb6 repair the selected physical bitmap in one draw,
; without advancing private animation. No authoritative instrument writes.
; Supported native scales 1..32 guarantee every legal height is encodable.
; Return 0/-3; invalid phase/scale/height leaves destination unchanged.
gauge_field_targets:
 movem.l d1-d5/a0-a4,-(sp)
 suba.w #8,sp
 movea.l sp,a4
 move.w GA_PHASE(a0),d0
 cmpi.w #1,d0
 bhi .bad
 eori.w #1,d0
 lea GA_VALUES(a0),a3
 adda.w d0,a3
 moveq #6,d5
.gauge:
 move.w 6(a1),d1
 beq .bad
 cmpi.w #32,d1
 bhi .bad
 moveq #0,d2
 move.b (a3),d2
 cmp.w d1,d2
 bhs .bad
 ; ceil(height*32/scale), with height=0 giving code 0.
 lsl.w #5,d2
 add.w d1,d2
 subq.w #1,d2
 divu.w d1,d2
 ori.b #$80,d2
 move.b d2,(a4)+
 addq.l #2,a3
 adda.w #12,a1
 dbf d5,.gauge
 movea.l sp,a4
 moveq #6,d5
.publish:
 move.b (a4)+,(a2)+
 dbf d5,.publish
 moveq #0,d0
 bra .done
.bad:
 moveq #-3,d0
.done:
 adda.w #8,sp
 movem.l (sp)+,d1-d5/a0-a4
 rts
