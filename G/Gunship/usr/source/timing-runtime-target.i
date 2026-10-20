; Deadline-owned target visibility/selection. The field consumer calls this
; after committed player motion and before geometry/weapons, never per draw.
; a0=arena. Return 0/-3 admission/-1 failure; preserve non-result registers.
; Native target commands are respected by seeding from the current block.
; Foreground serialized; drawing scratch/bitmap change, but no display swap.
timing_runtime_target:
 movem.l d1-d7/a0-a6,-(sp)
 movea.l a0,a6
 cmpi.l #1,RT_READY(a6)
 bne .bad
 tst.w RT_BOUNDARY_PHASE(a6)
 bne .retained
 cmpi.w #1,RT_CAPTURE_OWNER(a6)
 bne .bad
 bra .owner
.retained:
 ; Completing the retained field after native UI keeps producers excluded.
 cmpi.w #4,RT_BOUNDARY_PHASE(a6)
 bne .bad
 tst.w RT_CAPTURE_OWNER(a6)
 bne .bad
.owner:
 cmpi.w #3,RT_CONSUMER+TF_PHASE(a6)
 bne .bad
 cmpi.w #2,RT_SCHEDULER+TS_STATE(a6)
 bne .bad
 cmpi.w #1,RT_SCHEDULER+TS_DUE(a6)
 bne .bad
 move.l RT_SCHEDULER+TS_FIELD(a6),d1
 cmp.l RT_RECORD+TR_FIELD(a6),d1
 bne .bad
 cmp.l RT_CONSUMER+TF_FIELD(a6),d1
 bne .bad
 move.w RT_TARGET_PHASE(a6),d0
 beq .fresh
 cmpi.w #2,d0
 bne .bad
 cmp.l RT_TARGET_FIELD(a6),d1
 beq .bad
.fresh:
 lea RT_SCHEDULER(a6),a0
 bsr scheduler_check
 tst.l d0
 bne .failed
 ; Validate native descriptor offsets before any publication/phase change.
 movea.l RT_HUNKS(a6),a0
 adda.l #$a99e,a0
 lea 8(a0),a1
 moveq #4,d2
.validate:
 move.w (a1)+,d0
 cmpi.w #72,d0
 bhi .bad
 btst #0,d0
 bne .bad
 dbf d2,.validate
 move.l d1,RT_TARGET_FIELD(a6)
 move.w #1,RT_TARGET_PHASE(a6)
 lea RT_TARGET+WT_STATE(a6),a1
 moveq #WT_STATE_SIZE/2-1,d2
.seed:
 move.w (a0)+,(a1)+
 dbf d2,.seed
 movea.l RT_HUNKS+24(a6),a0
 lea $3b88(a0),a0
 lea RT_CAMERA(a6),a2
 bsr native_camera_build
 lea RT_VISIBILITY(a6),a0
 lea RT_TARGET(a6),a1
 lea RT_CAMERA(a6),a2
 movea.l RT_HUNKS(a6),a3
 adda.l #$c6a0,a3
 bsr visibility_raster_step
 tst.l d0
 bne .failed
 lea RT_TARGET(a6),a0
 lea WT_PIXELS(a0),a1
 lea WT_PALETTE+24(a0),a2
 bsr target_select_step
 tst.l d0
 bne .failed
 lea RT_TARGET+WT_STATE(a6),a0
 movea.l RT_HUNKS(a6),a1
 adda.l #$a99e,a1
 moveq #WT_STATE_SIZE/2-1,d2
.publish:
 move.w (a0)+,(a1)+
 dbf d2,.publish
 move.w #2,RT_TARGET_PHASE(a6)
 moveq #0,d0
 bra .done
.failed:
 move.w #3,RT_TARGET_PHASE(a6)
 moveq #-1,d0
 bra .done
.bad:
 moveq #-3,d0
.done:
 movem.l (sp)+,d1-d7/a0-a6
 rts
