; Experimental committed-view visibility acquisition. Not runtime-bound.
; Uses the native back buffer, raster scratch and blitter. Foreground only:
; no concurrent drawing, buffer swaps, target readers or native target hooks.
; Caller supplies committed poses, never predicted presentation inputs.
; Target state is borrowed/restored; bitmap and native render scratch are not.
VR_PREFIX_SIZE equ $74
VR_CODE_SIZE equ VR_PREFIX_SIZE+6
VR_H0 equ VR_CODE_SIZE
VR_H6 equ VR_H0+4
VR_SAVED_TARGET equ VR_H6+4
VR_SIZE equ VR_SAVED_TARGET+WT_STATE_SIZE

; a0=h0, a1=h6, a2=workspace. Return 0/-1, preserve other registers.
; Validate prefix bindings and native save/restore before any workspace write.
; Flush code cache after preparation. Native raster routines remain in place.
visibility_raster_prepare:
 movem.l d1-d4/a0-a6,-(sp)
 movea.l a0,a4
 movea.l a1,a5
 movea.l a2,a6
 lea $5c04(a4),a2
 cmpi.l #$48e71f1e,(a2)
 bne .bad
 cmpi.l #$4cdf78f8,$5cb8(a4)
 bne .bad
 cmpi.w #$4e75,$5cbc(a4)
 bne .bad
 lea visibility_raster_relocs(pc),a3
 moveq #13,d4
.check:
 move.w (a3)+,d1
 move.w (a3)+,d2
 moveq #0,d3
 move.w (a3)+,d3
 movea.l a4,a0
 tst.w d2
 beq .h0
 movea.l a5,a0
.h0:
 adda.l d3,a0
 cmpa.l 0(a2,d1.w),a0
 bne .bad
 dbf d4,.check
 movea.l a6,a1
 moveq #VR_PREFIX_SIZE/2-1,d1
.copy:
 move.w (a2)+,(a1)+
 dbf d1,.copy
 move.l #$4cdf78f8,(a1)+
 move.w #$4e75,(a1)+
 move.l a4,(a1)+
 move.l a5,(a1)+
 moveq #0,d0
 bra .done
.bad:
 moveq #-1,d0
.done:
 movem.l (sp)+,d1-d4/a0-a6
 rts

; a0=prepared VR, a1=prepared WT with previous selection/descriptor layout,
; a2=committed 12-byte camera, a3=committed 36-byte object coordinates.
; Return 0 with candidates, indexed pixels and rejected colors in WT;
; -1 missing binding, -3 invalid descriptor layout. Preserve other registers.
; Does not select/publish a target, swap buffers, advance effects or draw HUD.
; Caller may then use target_select_step with WT_PIXELS/WT_PALETTE+24.
visibility_raster_step:
 movem.l d1-d7/a0-a6,-(sp)
 movea.l a0,a6
 movea.l a1,a4
 tst.l VR_H0(a6)
 beq .bad_binding
 tst.l VR_H6(a6)
 beq .bad_binding
 moveq #4,d1
 lea WT_STATE+8(a4),a0
.validate:
 move.w (a0)+,d0
 cmpi.w #72,d0
 bhi .bad_state
 btst #0,d0
 bne .bad_state
 dbf d1,.validate
 ; Preserve the native target block while collecting this committed view.
 movea.l VR_H0(a6),a0
 adda.l #$a99e,a0
 lea VR_SAVED_TARGET(a6),a1
 lea WT_STATE(a4),a5
 moveq #WT_STATE_SIZE/2-1,d1
.borrow:
 move.w (a0),(a1)+
 move.w (a5)+,(a0)+
 dbf d1,.borrow
 movea.l VR_H0(a6),a0
 adda.l #$a9a0,a0
 clr.w (a0)
 ; The native prefix binds the back buffer and builds cell/transform scratch.
 movea.l a2,a0
 movea.l a3,a1
 movea.l VR_H6(a6),a2
 lea $3904(a2),a3
 bsr scene_state_build
 jsr (a6)
 ; Finish DMA before reading any pixels (including old-Agnus initial read).
 tst.w $dff002
.wait:
 btst #6,$dff002
 bne .wait
 movea.l VR_H0(a6),a0
 adda.l #$a99e,a0
 lea VR_SAVED_TARGET(a6),a1
 lea WT_STATE(a4),a2
 moveq #WT_STATE_SIZE/2-1,d1
.capture:
 move.w (a0),(a2)+
 move.w (a1)+,(a0)+
 dbf d1,.capture
 ; Snapshot the native palette predicate for this view, before selection.
 movea.l VR_H6(a6),a0
 lea $16dc(a0),a1
 tst.b $3b9e(a0)
 beq .palette
 adda.w #$100,a1
.palette:
 move.b 24(a1),WT_PALETTE+24(a4)
 move.b 25(a1),WT_PALETTE+25(a4)
 clr.l WT_PIXELS(a4)
 clr.w WT_PIXELS+4(a4)
 moveq #0,d7
 move.w WT_STATE+2(a4),d7
 cmpi.w #5,d7
 bhi .bad_state
 subq.w #1,d7
 bmi .ok
 movea.l VR_H0(a6),a5
 adda.l #$825e,a5
 lea WT_STATE+$80(a4),a3
 lea WT_PIXELS(a4),a2
 moveq #0,d6
.pixels:
 move.w 0(a3,d6.w),d0
 move.w 10(a3,d6.w),d1
 jsr (a5)
 move.w d6,d2
 lsr.w #1,d2
 move.b d0,0(a2,d2.w)
 addq.w #2,d6
 dbf d7,.pixels
.ok:
 moveq #0,d0
 bra .done
.bad_binding:
 moveq #-1,d0
 bra .done
.bad_state:
 moveq #-3,d0
.done:
 movem.l (sp)+,d1-d7/a0-a6
 rts

; Prefix offset, source hunk, source offset. No PC-relative branches in prefix.
visibility_raster_relocs:
 dc.w $06,6,$38f6,$0c,6,$15dc,$16,0,$84e2,$1c,0,$6980
 dc.w $26,6,$3958,$30,0,$7a1c,$3e,0,$7a1c,$48,0,$5f8e
 dc.w $4e,0,$5cbe,$54,0,$5ea4,$5a,0,$77b8,$62,0,$8524
 dc.w $68,0,$60a8,$70,0,$8524
