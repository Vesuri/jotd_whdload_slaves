; Project native candidates privately, without rasterization or pixel sampling.
; Requires scene-private, target-select, target-collect. Do NOT use this as a
; visibility oracle: selection still needs pixels from the same committed view.
SCT_TARGET equ SCENE_SIZE
SCT_COLLECTOR equ SCT_TARGET+4
SCT_SELECTION equ SCT_COLLECTOR+4 ; target snapshot before projectile overlay
SCT_SIZE equ SCT_SELECTION+WT_STATE_SIZE
; a0=h0,a1=h4,a2=h6,a3=SCT_SIZE workspace,a4=WT,a5=collector. Return 0/-1.
; Failed setup is not callable; no native writes. Flush clones before use.
scene_target_prepare:
 movem.l d1-d7/a0-a6,-(sp)
 suba.w #24,sp
 movem.l a0-a5,(sp)
 ; Validate drawing calls that this mode removes from point-object handling.
 lea scene_target_draw_sites(pc),a6
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
 lea scene_target_draw_sites(pc),a6
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

; Forecast preparation: original prepare ABI plus a6=stable, read-only player
; record used by this private scene. Caller updates its contents between steps.
; Bind map-cell X/Y and acquisition view mode to that record, not live player
; bytes. Camera remains a separate explicit step input (including view offsets).
; Other shared model/limit dependencies still require caller certification.
; Flush cloned code after preparation, as for scene_target_prepare.
scene_target_player_prepare:
 movem.l d1/a0-a2,-(sp)
 cmpi.w #$1439,$61c0(a0)
 bne .bad
 lea $3b88(a2),a1
 cmpa.l $61c2(a0),a1
 bne .bad
 cmpi.w #$1439,$61d2(a0)
 bne .bad
 addq.l #2,a1
 cmpa.l $61d4(a0),a1
 bne .bad
 adda.l #$a4f6,a0
 cmpi.w #$4a39,(a0)
 bne .bad
 lea $3ba2(a2),a1
 cmpa.l 2(a0),a1
 bne .bad
 movem.l (sp),d1/a0-a2
 bsr scene_target_prepare
 tst.l d0
 bne .done
 move.l a6,$61c2-SCENE_START(a3)
 lea 2(a6),a0
 move.l a0,$61d4-SCENE_START(a3)
 lea $1a(a6),a0
 move.l a0,$a4f8-$a450(a5)
 moveq #0,d0
 bra .done
.bad:
 moveq #-1,d0
.done:
 movem.l (sp)+,d1/a0-a2
 rts
scene_target_draw_sites:
 dc.w $63b0,$bc32,$63c4,$8208,$63ce,$8228


; a0=prepared SCT, a1=committed camera, a2=committed object coordinates.
; Candidate publication matches native +5c78: after +60a8, before +6224.
; The later overlay still contributes to the flight-end flag, but its target
; writes cannot change the selection input for this committed view.
; Return 0/1 plane flag, -3 bad target layout/binding, -1 missing scene binding.
; Only private scene/target/stack writes. Previous target identity is retained.
scene_target_step:
 movem.l d1-d7/a0-a6,-(sp)
 clr.l -(sp)
 bra scene_target_common

; Same inputs, but only collect pre-overlay target candidates. Return 0 on
; success; never interpret it as a flight-end flag. No overlay traversal or
; SCT_SELECTION copy is needed when the caller wants only the candidate list.
; Geometry/visibility dependencies and private-write rules remain unchanged.
scene_target_candidates_step:
 movem.l d1-d7/a0-a6,-(sp)
 move.l #1,-(sp)
scene_target_common:
 movea.l a0,a6
 tst.l SCENE_H0(a6)
 beq .scene_bad
 tst.l SCENE_H6(a6)
 beq .scene_bad
 movea.l SCT_TARGET(a6),a3
 move.l a3,d0
 beq .bad
 tst.l SCT_COLLECTOR(a6)
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
 movea.l SCT_TARGET(a6),a3
 clr.w WT_STATE+2(a3)
 ; Same camera/context construction as scene_private_step.
 ; Loader-time clones precede native transform-range initialization.
 ; Refresh the coordinate table just as scene_private_step does; otherwise
 ; cold forecast collectors can project zero/stale depth and admit a target
 ; the real next world rejects. Rebuild actor coordinates afterward.
 movea.l SCENE_H6(a6),a3
 lea $18dc(a3),a3
 lea SCENE_COORD(a6),a4
 moveq #$b8/2-1,d1
.coords:
 move.w (a3)+,(a4)+
 dbf d1,.coords
 movea.l a1,a0
 movea.l a2,a1
 movea.l SCENE_H6(a6),a2
 lea SCENE_CONTEXT+14(a6),a3
 bsr scene_state_build
 lea SCENE_CONTEXT(a6),a5
 lea $15dc(a2),a0
 move.l a0,$5e(a5)
 clr.b $62(a5)
 lea $5c2e-SCENE_START(a6),a0
 jsr (a0)
 lea $60a8-SCENE_START(a6),a0
 jsr (a0)
 tst.l (sp)
 bne .candidates_done
 ; Native panel selection is at this boundary, before projectile overlays.
 movea.l SCT_TARGET(a6),a0
 lea WT_STATE(a0),a0
 lea SCT_SELECTION(a6),a1
 moveq #WT_STATE_SIZE/2-1,d1
.capture:
 move.w (a0)+,(a1)+
 dbf d1,.capture
 lea $6224-SCENE_START(a6),a0
 jsr (a0)
 movea.l SCT_TARGET(a6),a0
 lea WT_STATE(a0),a0
 lea SCT_SELECTION(a6),a1
 moveq #WT_STATE_SIZE/2-1,d1
.publish:
 move.w (a1)+,(a0)+
 dbf d1,.publish
 moveq #0,d0
 move.b $62(a5),d0
 andi.w #1,d0
 bra .done
.candidates_done:
 moveq #0,d0
 bra .done
.scene_bad:
 moveq #-1,d0
 bra .done
.bad:
 moveq #-3,d0
.done:
 addq.l #4,sp
 movem.l (sp)+,d1-d7/a0-a6
 rts
