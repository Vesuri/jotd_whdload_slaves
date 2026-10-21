; Private native target selection, with explicit committed-view pixel samples.
; This does not acquire visibility, collect candidates or publish a lock.
WT_CODE_SIZE equ $158 ; native +a58c..+a6e4
WT_STATE equ WT_CODE_SIZE
WT_STATE_SIZE equ $a8 ; native +a99e..+aa46
WT_PIXELS equ WT_STATE+WT_STATE_SIZE
WT_PALETTE equ WT_PIXELS+6
WT_MODE equ WT_PALETTE+26
WT_SIZE equ WT_MODE+2

; a0=hunk 0, a1=hunk 6, a2=even private workspace.
; Validate every relocation before writes, then copy native selection code.
; State is initialized empty. Caller supplies candidate state and pixel inputs.
; Return 0/-1, preserve others. Flush code cache before first use.
target_select_prepare:
 movem.l d1-d4/a0-a6,-(sp)
 movea.l a0,a4
 movea.l a1,a5
 movea.l a2,a6
 lea target_select_relocs(pc),a3
 moveq #29,d4
.check:
 move.w (a3)+,d1
 move.w (a3)+,d2
 moveq #0,d3
 move.w (a3)+,d3
 addq.l #2,a3
 movea.l a4,a0
 tst.w d2
 beq .h0
 movea.l a5,a0
.h0:
 adda.l d3,a0
 movea.l a4,a1
 adda.l #$a58c,a1
 cmpa.l 0(a1,d1.w),a0
 bne .bad
 dbf d4,.check
 cmpi.w #$4a79,(a1)
 bne .bad
 cmpi.w #$4e75,WT_CODE_SIZE-2(a1)
 bne .bad
 movea.l a1,a0
 movea.l a6,a1
 move.w #WT_CODE_SIZE/2-1,d1
.copy:
 move.w (a0)+,(a1)+
 dbf d1,.copy
 move.w #(WT_SIZE-WT_CODE_SIZE)/2-1,d1
.clear:
 clr.w (a1)+
 dbf d1,.clear
 lea target_select_relocs(pc),a3
 moveq #29,d4
.patch:
 move.w (a3)+,d1
 addq.l #4,a3
 move.w (a3)+,d2
 lea 0(a6,d2.w),a0
 move.l a0,0(a6,d1.w)
 dbf d4,.patch
 lea target_select_pixel(pc),a0
 move.l a0,$a6b0-$a58c(a6)
 moveq #0,d0
 bra .done
.bad:
 moveq #-1,d0
.done:
 movem.l (sp)+,d1-d4/a0-a6
 rts

; a0=prepared workspace, a1=five indexed pixel bytes, a2=two rejected colors.
; WT_STATE holds a native-shaped candidate/selection snapshot supplied by caller.
; Samples must come from the same committed view that produced the candidates.
; Return 0 selected/evaluated, -3 invalid count/descriptor offset, preserve rest.
; Only private state/stack writes. No native state, bitmap, OS or RNG access.
target_select_step:
 movem.l d1-d7/a0-a6,-(sp)
 movea.l a0,a6
 cmpi.w #5,WT_STATE+2(a6)
 bhi .bad
 moveq #4,d1
 lea WT_STATE+8(a6),a3
.validate:
 move.w (a3)+,d0
 cmpi.w #72,d0
 bhi .bad
 btst #0,d0
 bne .bad
 dbf d1,.validate
 lea WT_PIXELS(a6),a3
 moveq #4,d1
.pixels:
 move.b (a1)+,(a3)+
 dbf d1,.pixels
 move.b (a2)+,WT_PALETTE+24(a6)
 move.b (a2),WT_PALETTE+25(a6)
 clr.b WT_MODE(a6)
 jsr (a6)
 moveq #0,d0
 bra .done
.bad:
 moveq #-3,d0
.done:
 movem.l (sp)+,d1-d7/a0-a6
 rts

; Visibility-independent homing dependency for zero/one collected candidate.
; a0=WT candidate workspace, a1=distinct private 12-byte output.
; Return 0 copied, -3 ambiguous/invalid layout (output unchanged).
; Native selection leaves AA0A..AA15 unchanged with no candidates. With one,
; acceptance only copies its first identity/generation onto themselves;
; rejection leaves them intact. Status/selected-panel state is NOT certified.
; Caller must separately certify the forecast geometry and world dependencies.
; Never publishes a native target or supplies collision/AI state.
target_selector_single:
 movem.l d1-d2/a0-a2,-(sp)
 cmpi.w #1,WT_STATE+2(a0)
 bhi .uncertain
 lea WT_STATE+8(a0),a2
 moveq #4,d2
.validate:
 move.w (a2)+,d1
 cmpi.w #72,d1
 bhi .uncertain
 btst #0,d1
 bne .uncertain
 dbf d2,.validate
 lea WT_STATE+$6c(a0),a2
 move.l (a2)+,(a1)+
 move.l (a2)+,(a1)+
 move.l (a2),(a1)
 moveq #0,d0
 bra .done
.uncertain:
 moveq #-3,d0
.done:
 movem.l (sp)+,d1-d2/a0-a2
 rts

; Native ReadPixel ABI replacement: A0 is the candidate list cursor.
; A6 is private workspace retained by the selector. Preserve other registers.
target_select_pixel:
 move.l a1,-(sp)
 move.l a0,d0
 lea WT_STATE+$6c(a6),a1
 sub.l a1,d0
 lsr.l #1,d0
 lea WT_PIXELS(a6),a1
 move.b 0(a1,d0.w),d0
 andi.l #$ff,d0
 movea.l (sp)+,a1
 rts

; Verified HUNK relocations: clone offset, source hunk, source offset,
; private destination offset. Pixel-call entry is patched separately.
target_select_relocs:
 dc.w $0002,0,$a9a0,WT_STATE+$0002
 dc.w $000c,0,$a99e,WT_STATE+$0000
 dc.w $0018,0,$aa0a,WT_STATE+$006c
 dc.w $0024,0,$a9a0,WT_STATE+$0002
 dc.w $0030,0,$a9a2,WT_STATE+$0004
 dc.w $0042,0,$a9a4,WT_STATE+$0006
 dc.w $004a,0,$a6a2,$0116
 dc.w $0054,0,$a99e,WT_STATE+$0000
 dc.w $0062,0,$a9a0,WT_STATE+$0002
 dc.w $006c,0,$a68e,$0102
 dc.w $0076,0,$aa0a,WT_STATE+$006c
 dc.w $007e,0,$a68e,$0102
 dc.w $008a,0,$aa0a,WT_STATE+$006c
 dc.w $0090,0,$a9a2,WT_STATE+$0004
 dc.w $009a,0,$a9a4,WT_STATE+$0006
 dc.w $00a0,0,$aa14,WT_STATE+$0076
 dc.w $00a8,0,$aa1e,WT_STATE+$0080
 dc.w $00b0,0,$aa28,WT_STATE+$008a
 dc.w $00bc,0,$aa32,WT_STATE+$0094
 dc.w $00c2,0,$a9a6,WT_STATE+$0008
 dc.w $00cc,0,$a9b0,WT_STATE+$0012
 dc.w $00e0,0,$a9a0,WT_STATE+$0002
 dc.w $00e8,0,$a99e,WT_STATE+$0000
 dc.w $00f0,0,$a99e,WT_STATE+$0000
 dc.w $00f6,0,$a9a0,WT_STATE+$0002
 dc.w $00fc,0,$a9a4,WT_STATE+$0006
 dc.w $010e,0,$a9a0,WT_STATE+$0002
 dc.w $0124,0,$825e,0
 dc.w $012c,6,$16dc,WT_PALETTE
 dc.w $0132,6,$3b9e,WT_MODE
