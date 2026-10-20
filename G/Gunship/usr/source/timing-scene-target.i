; Project native candidates privately, without rasterization or pixel sampling.
; Requires scene-private, target-select, target-collect. Do NOT use this as a
; visibility oracle: selection still needs pixels from the same committed view.
SCT_TARGET equ SCENE_SIZE
SCT_COLLECTOR equ SCT_TARGET+4
SCT_SIZE equ SCT_COLLECTOR+4
; a0=h0,a1=h4,a2=h6,a3=SCT_SIZE workspace,a4=WT,a5=collector. Return 0/-1.
; Failed setup is not callable; no native writes. Flush clones before use.
scene_target_prepare:
 movem.l d1-d7/a0-a6,-(sp)
 suba.w #24,sp
 movem.l a0-a5,(sp)
 ; Validate drawing calls that this mode removes from point-object handling.
 lea .draw_sites(pc),a6
 moveq #2,d7
.check:
 move.w (a6)+,d1
 moveq #0,d2
 move.w (a6)+,d2
 cmpi.w #$4eb9,0(a0,d1.w)
 bne .bad
 movea.l a0,a1
 adda.l d2,a1
 cmpa.l 2(a0,d1.w),a1
 bne .bad
 dbf d7,.check
 cmpi.w #$4eb9,$63d4(a0)
 bne .bad
 movea.l a0,a1
 adda.l #$a450,a1
 cmpa.l $63d6(a0),a1
 bne .bad
 movea.l 8(sp),a1
 movea.l 12(sp),a2
 bsr scene_private_prepare
 tst.l d0
 bne .done
 movem.l (sp),a0-a5
 bsr target_collect_prepare
 tst.l d0
 bne .done
 movea.l (sp),a0
 movea.l 12(sp),a1
 ; Restore the full native vertex transform/projector prologue, replacing
 ; traversal-only optimization. Its two pointers belong to private scratch.
 lea $6642(a0),a2
 lea $6642-SCENE_START(a1),a3
 moveq #6,d1
.restore:
 move.w (a2)+,(a3)+
 dbf d1,.restore
 lea $6aca-SCENE_START(a1),a2
 move.l a2,$6644-SCENE_START(a1)
 lea $75e6-SCENE_START(a1),a2
 move.l a2,$664a-SCENE_START(a1)
 move.l $6372(a0),$6372-SCENE_START(a1)
 move.w #$4eb9,$6356-SCENE_START(a1)
 move.l 20(sp),$6358-SCENE_START(a1)
 move.l 20(sp),$63d6-SCENE_START(a1)
 lea .draw_sites(pc),a6
 moveq #2,d7
.remove:
 move.w (a6)+,d1
 addq.l #2,a6
 subi.w #SCENE_START,d1
 move.l #$4e714e71,0(a1,d1.w)
 move.w #$4e71,4(a1,d1.w)
 dbf d7,.remove
 move.l 16(sp),SCT_TARGET(a1)
 move.l 20(sp),SCT_COLLECTOR(a1)
 moveq #0,d0
 bra .done
.bad:
 moveq #-1,d0
.done:
 adda.w #24,sp
 movem.l (sp)+,d1-d7/a0-a6
 rts
.draw_sites:
 dc.w $63b0,$bc32,$63c4,$8208,$63ce,$8228


; a0=prepared SCT, a1=committed camera, a2=committed object coordinates.
; Validate target descriptor layout, discard the previous candidate count,
; then project/collect the current view. Return 0/1 plane flag, -3 bad layout
; or target binding, -1 missing scene binding.
; Only private scene/target/stack writes. Previous target identity is retained.
scene_target_step:
 movem.l d1/a0-a3,-(sp)
 movea.l SCT_TARGET(a0),a3
 move.l a3,d0
 beq .bad
 tst.l SCT_COLLECTOR(a0)
 beq .bad
 moveq #4,d1
 lea WT_STATE+8(a3),a3
.validate:
 move.w (a3)+,d0
 cmpi.w #72,d0
 bhi .bad
 btst #0,d0
 bne .bad
 dbf d1,.validate
 movea.l SCT_TARGET(a0),a3
 clr.w WT_STATE+2(a3)
 bsr scene_private_step
 bra .done
.bad:
 moveq #-3,d0
.done:
 movem.l (sp)+,d1/a0-a3
 rts
