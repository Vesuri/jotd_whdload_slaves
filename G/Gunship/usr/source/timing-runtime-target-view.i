; Borrow the current-view projection only during the native panel painter.
; a0=arena, a5=native scene context; foreground serialized with world consumers.
; Return 0/-3, preserve other registers. Native panel writes to the target
; block are discarded; drawing/UI scratch outside that block remains native.
; An invalid selection in targeting mode waits for the next world selection:
; the native painter would otherwise reopen the map between world deadlines.
timing_runtime_target_panel:
 movem.l d1-d7/a0-a6,-(sp)
 movea.l a0,a6
 cmpi.l #1,RT_READY(a6)
 bne .bad
 cmpi.w #1,RT_CAPTURE_OWNER(a6)
 bne .bad
 tst.w RT_BOUNDARY_PHASE(a6)
 bne .bad
 cmpi.w #1,RT_VIEW_PHASE(a6)
 bne .bad
 movea.l RT_HUNKS(a6),a0
 adda.l #$a99e,a0
 lea RT_VIEW_SAVED(a6),a1
 moveq #WT_STATE_SIZE/2-1,d1
.save:
 move.w (a0)+,(a1)+
 dbf d1,.save
 tst.b RT_VIEW_SAVED(a6)
 bpl .paint
 movea.l RT_HUNKS+16(a6),a0
 tst.b $1c5(a0)
 beq .close
.paint:
 lea RT_VIEW(a6),a0
 movea.l RT_HUNKS(a6),a1
 adda.l #$a99e,a1
 bsr target_view_build
 ; Return 0 leaves committed inputs intact. The draw guard hides its stale
 ; marker, while the panel still updates native sprites and UI mode.
 move.w #2,RT_VIEW_PHASE(a6)
 movea.l RT_HUNKS(a6),a2
 adda.w #$468c,a2
 move.l a6,-(sp)
 jsr (a2)
 movea.l (sp)+,a6
 lea RT_VIEW_SAVED(a6),a0
 movea.l RT_HUNKS(a6),a1
 adda.l #$a99e,a1
 moveq #WT_STATE_SIZE/2-1,d1
.restore:
 move.w (a0)+,(a1)+
 dbf d1,.restore
.close:
 clr.w RT_VIEW_PHASE(a6)
 moveq #0,d0
 bra .done
.bad:
 moveq #-3,d0
.done:
 movem.l (sp)+,d1-d7/a0-a6
 rts
