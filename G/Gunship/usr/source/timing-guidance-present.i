; Retain the latest native request for each guidance hardware sprite.
; Foreground field owner captures; render owner presents, serialized by caller.
; No gameplay state writes or graphics calls while capturing.
GP_H0 equ 0
GP_H6 equ 4
GP_MOVE equ 8
GP_CHANGE equ 12
GP_FIRST equ 16
GP_SECOND equ GP_FIRST+20
GP_DIRTY equ GP_SECOND+20
GP_SIZE equ GP_DIRTY+2
; Each request: viewport, sprite, signed X, signed Y, image (five longs).

; a0=context, a1=hunk 0, a2=hunk 6. Validated native layout required.
; Preserve all registers. Reset requests to hidden, dirty for first render.
guidance_present_init:
 movem.l a1/a3,-(sp)
 move.l a1,GP_H0(a0)
 move.l a2,GP_H6(a0)
 movea.l a1,a3
 adda.l #$f048,a3
 move.l a3,GP_MOVE(a0)
 movea.l a1,a3
 adda.l #$f02c,a3
 move.l a3,GP_CHANGE(a0)
 movem.l (sp)+,a1/a3
 bra guidance_present_reset

; a0=context. Rebase visual requests without executing graphics callbacks.
guidance_present_reset:
 movem.l d0-d1/a0-a2,-(sp)
 movea.l GP_H6(a0),a2
 lea GP_FIRST(a0),a1
 moveq #1,d1
.slot:
 move.l $47b8(a2),(a1)
 lea $4d1c(a2),a0
 tst.w d1
 bne .first
 adda.w #12,a0
.first:
 move.l a0,4(a1)
 moveq #-32,d0
 move.l d0,8(a1)
 move.l d0,12(a1)
 move.l $4d54(a2),16(a1)
 adda.w #20,a1
 dbf d1,.slot
 move.w #3,(a1) ; GP_DIRTY follows both descriptors
 movem.l (sp)+,d0-d1/a0-a2
 rts

; a0=prepared guidance clone, a1=initialized presentation context.
; Bind only an update-only clone. Validate all sites before modifying it.
; Flush instruction caches before execution. Return 0/-1, preserve others.
guidance_present_bind:
 movem.l d1-d2/a0-a3,-(sp)
 lea .sites(pc),a2
 moveq #3,d2
.check:
 move.w (a2)+,d1
 cmpi.l #$4e714e71,0(a0,d1.w)
 bne .bad
 cmpi.w #$4e71,4(a0,d1.w)
 bne .bad
 dbf d2,.check
 move.l a1,FG_PRESENT(a0)
 lea guidance_capture_hide(pc),a3
 lea .sites(pc),a2
 moveq #3,d2
.patch:
 move.w (a2)+,d1
 move.w #$4eb9,0(a0,d1.w)
 move.l a3,2(a0,d1.w)
 lea guidance_capture_sprite(pc),a3
 dbf d2,.patch
 moveq #0,d0
 bra .done
.bad:
 moveq #-1,d0
.done:
 movem.l (sp)+,d1-d2/a0-a3
 rts
.sites:
 dc.w $44,$c2,$f6,$114

; Native clone leaves a0 pointing to its base at all four display sites.
; Capture before native phase increment, with the native table selections.
guidance_capture_sprite:
 movem.l d0-d5/a0-a2/a6,-(sp)
 movea.l FG_PRESENT(a0),a0
 movea.l GP_H0(a0),a1
 adda.l #$a44d,a1
 moveq #0,d2
 move.b (a1),d2
 add.w d2,d2
 movea.l GP_H6(a0),a2
 lea $3aec(a2),a1
 move.w 0(a1,d2.w),d1
 move.w 0(a4,d2.w),d3
 moveq #0,d5
 move.b 0(a3,d2.w),d5
 move.w 0(a5,d5.w),d5
 lea $4d54(a2),a1
 moveq #-32,d0
 tst.w d5
 bmi .hidden
 move.w d3,d0
 adda.w d5,a1
.hidden:
 move.l (a1),d4
 lea $4d1c(a2),a1
 cmpa.l a1,a6
 bne .second
 ori.w #1,GP_DIRTY(a0)
 lea GP_FIRST(a0),a1
 bra .store
.second:
 ori.w #2,GP_DIRTY(a0)
 lea GP_SECOND(a0),a1
.store:
 move.l $47b8(a2),(a1)
 move.l a6,4(a1)
 ext.l d0
 ext.l d1
 move.l d0,8(a1)
 move.l d1,12(a1)
 move.l d4,16(a1)
 movem.l (sp)+,d0-d5/a0-a2/a6
 rts

guidance_capture_hide:
 move.l a0,-(sp)
 movea.l FG_PRESENT(a0),a0
 bsr guidance_present_reset
 movea.l (sp)+,a0
 rts

; a0=context. Render dirty sprites using the original library wrappers.
; Latest request per sprite wins; no gameplay fields or phase are changed.
; Return number presented, preserve other registers. Caller excludes capture.
guidance_present:
 movem.l d1-d7/a0-a6,-(sp)
 movea.l a0,a5
 move.w GP_DIRTY(a5),d7
 lea GP_FIRST(a5),a4
 moveq #0,d6
 moveq #1,d5
.slot:
 lsr.w #1,d7
 bcc .next
 move.l 16(a4),-(sp)
 move.l 12(a4),-(sp)
 move.l 8(a4),-(sp)
 move.l 4(a4),-(sp)
 move.l (a4),-(sp)
 movea.l GP_MOVE(a5),a0
 jsr (a0)
 move.l 16(sp),8(sp)
 movea.l GP_CHANGE(a5),a0
 jsr (a0)
 adda.w #20,sp
 addq.w #1,d6
.next:
 adda.w #20,a4
 dbf d5,.slot
 clr.w GP_DIRTY(a5)
 move.l d6,d0
 movem.l (sp)+,d1-d7/a0-a6
 rts
