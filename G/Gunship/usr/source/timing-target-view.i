; Presentation-only capture of the world-selected object from native projection.
; Uses the original collector filters, but never selects or samples pixels.
; The caller resets before a frame and invokes capture at native collector sites.
; Native scene scratch/model data must be stable during each capture.
TPV_H0 equ 0
TPV_STATE equ 4 ; 168-byte private target block
TPV_VALID equ TPV_STATE+WT_STATE_SIZE
TPV_CODE equ TPV_VALID+2
TPV_SIZE equ TPV_CODE+WTC_CODE_SIZE

; a0=h0,a1=h4,a2=h6,a3=TPV_SIZE destination. Return 0/-1, preserve others.
; Validate every native relocation before copying. Only target-block operands
; are redirected; scene operands read the projection already made by rendering.
; Failed preparation is not callable. Flush code before first capture.
target_view_prepare:
 movem.l d1-d7/a0-a6,-(sp)
 suba.w #16,sp
 movem.l a0-a3,(sp)
 lea target_collect_relocs(pc),a6
 moveq #(target_collect_relocs_end-target_collect_relocs)/8-1,d7
.check:
 move.w (a6)+,d1
 move.w (a6)+,d2
 moveq #0,d3
 move.w (a6)+,d3
 addq.l #2,a6
 movea.l 0(sp,d2.w),a0
 adda.l d3,a0
 movea.l (sp),a1
 adda.l #$a450,a1
 cmpa.l 0(a1,d1.w),a0
 bne .bad
 dbf d7,.check
 cmpi.w #$3239,(a1)
 bne .bad
 cmpi.w #$4e75,WTC_CODE_SIZE-2(a1)
 bne .bad
 movea.l 12(sp),a3
 move.l (sp),TPV_H0(a3)
 clr.w TPV_VALID(a3)
 lea TPV_CODE(a3),a2
 move.w #WTC_CODE_SIZE/2-1,d1
.copy:
 move.w (a1)+,(a2)+
 dbf d1,.copy
 lea target_collect_relocs(pc),a6
 moveq #(target_collect_relocs_end-target_collect_relocs)/8-1,d7
.patch:
 move.w (a6)+,d1
 addq.l #4,a6
 move.w (a6)+,d2
 cmpi.w #$ffff,d2
 beq .next
 btst #15,d2
 beq .next
 andi.w #$7fff,d2
 subi.w #WT_STATE,d2
 lea TPV_STATE(a3),a0
 adda.w d2,a0
 lea TPV_CODE(a3),a1
 move.l a0,0(a1,d1.w)
.next:
 dbf d7,.patch
 moveq #0,d0
 bra .done
.bad:
 moveq #-1,d0
.done:
 adda.w #16,sp
 movem.l (sp)+,d1-d7/a0-a6
 rts

; a0=prepared TV,a1=committed 168-byte target block. Return 0/-3.
; Descriptor offsets must be even and 0..72. Invalid reset writes nothing.
target_view_reset:
 movem.l d1-d2/a0-a2,-(sp)
 lea 8(a1),a2
 moveq #4,d1
.check:
 move.w (a2)+,d2
 cmpi.w #72,d2
 bhi .bad
 btst #0,d2
 bne .bad
 dbf d1,.check
 clr.w TPV_VALID(a0)
 lea TPV_STATE(a0),a2
 moveq #WT_STATE_SIZE/2-1,d1
.copy:
 move.w (a1)+,(a2)+
 dbf d1,.copy
 clr.w TPV_STATE+2(a0)
 moveq #0,d0
 bra .done
.bad:
 moveq #-3,d0
.done:
 movem.l (sp)+,d1-d2/a0-a2
 rts

; a0=TV,a5=native scene context. Preserve all except result D0/CCR.
; Return 1 captured, 0 ignored/clipped. Match committed identity first so
; unrelated candidates cannot fill the five-slot list ahead of this object.
; Negative identities follow the native selector's subtype-independent rule.
target_view_capture:
 movem.l d1-d7/a0-a6,-(sp)
 movea.l a0,a6
 cmpi.b #2,TPV_STATE(a6)
 bne .ignored
 movea.l TPV_H0(a6),a0
 move.w $6ac6(a0),d0
 cmp.w TPV_STATE+4(a6),d0
 bne .ignored
 tst.w d0
 bmi .matched
 move.w $5b00(a0),d0
 cmp.w TPV_STATE+6(a6),d0
 bne .ignored
.matched:
 clr.w TPV_STATE+2(a6)
 lea TPV_CODE(a6),a0
 jsr (a0)
 tst.w TPV_STATE+2(a6)
 beq .ignored
 move.w #1,TPV_VALID(a6)
 moveq #1,d0
 bra .done
.ignored:
 moveq #0,d0
.done:
 movem.l (sp)+,d1-d7/a0-a6
 rts

; a0=TV,a1=168-byte presentation destination. Return 1 if a current projection
; exists, 0 otherwise (no output writes). Caller must hide the current-view
; marker when absent, not display the previous frame's projection.
; Keep status/selected identity from reset; normalize the selected descriptor
; to slot zero as native selection does, without running selection or RNG.
target_view_build:
 movem.l d1/a0-a3,-(sp)
 tst.w TPV_VALID(a0)
 beq .absent
 lea TPV_STATE(a0),a2
 movea.l a1,a3
 moveq #WT_STATE_SIZE/2-1,d1
.copy:
 move.w (a2)+,(a3)+
 dbf d1,.copy
 move.w TPV_STATE+8(a0),d1
 lea TPV_STATE+18(a0),a2
 adda.w d1,a2
 lea 18(a1),a3
 moveq #8,d1
.descriptor:
 move.w (a2)+,(a3)+
 dbf d1,.descriptor
 clr.w 2(a1)
 moveq #1,d0
 bra .done
.absent:
 moveq #0,d0
.done:
 movem.l (sp)+,d1/a0-a3
 rts
