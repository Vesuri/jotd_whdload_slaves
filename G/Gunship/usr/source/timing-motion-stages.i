; Requires timing-motion-preview.i. Standalone, not installed.
; Seven immutable native slices expose integration order and raw terms.
MS_COUNT equ 7
MS_CODE_SIZE equ MP_CODE_SIZE*MS_COUNT
MS_TERMS_SIZE equ 12
; Terms: d0.l, d1.l, d2.l from the preceding slice. Initialize to zero.
; Caller supplies a private player record; slices update it in place.

; a0 = validated 0658 code hunk, a1 = even MS_CODE_SIZE-byte destination.
; d0=0 success / -1 signature failure; preserves other registers.
; Source must be stable; buffers must not overlap. Flush instruction caches
; after preparation and before execution. No runtime code rewriting.
motion_stages_prepare:
	movem.l d1-d7/a0-a6,-(sp)
	bsr motion_preview_prepare
	tst.l d0
	bne .done
	lea MP_CODE_SIZE(a1),a3
	moveq #MS_COUNT-2,d2
.clone:
	movea.l a1,a2
	move.w #MP_CODE_SIZE/2-1,d1
.copy:
	move.w (a2)+,(a3)+
	dbf d1,.copy
	dbf d2,.clone
	; Each clone returns at one boundary; relative branches/tables stay put.
	lea motion_stage_ends(pc),a2
	movea.l a1,a3
	moveq #MS_COUNT-1,d2
.end:
	move.w (a2)+,d1
	move.w #$4e75,0(a3,d1.w)
	adda.w #MP_CODE_SIZE,a3
	dbf d2,.end
	moveq #0,d0
.done:
	movem.l (sp)+,d1-d7/a0-a6
	rts

; d0.l = stage 0..6, a0 = private record, a1 = prepared code, a2 = terms.
; d0=0 success / -1 invalid stage; preserves other registers.
; Stages must be called in order unless caller supplies corresponding
; record/terms dependencies. Native world RNG/contact effects are excluded.
motion_stage:
	movem.l d1-d7/a0-a6,-(sp)
	cmpi.l #MS_COUNT,d0
	bhs .bad
	move.w d0,d3
	mulu.w #MP_CODE_SIZE,d0
	adda.l d0,a1
	move.w d3,d4
	add.w d4,d4
	lea motion_stage_entries(pc),a3
	move.w 0(a3,d4.w),d4
	adda.w d4,a1
	movea.l a0,a5
	movea.l a2,a6
	movem.l (a6),d0-d2
	; Horizontal displacement must see the caller's committed/scaled speed,
	; not a stale whole-tick speed in the previous slice's d0.
	cmpi.w #5,d3
	bne .execute
	move.w $2a(a5),d0
.execute:
	jsr (a1)
	movem.l d0-d2,(a6)
	moveq #0,d0
	bra .done
.bad:
	moveq #-1,d0
.done:
	movem.l (sp)+,d1-d7/a0-a6
	rts

; 0: power + heading/track.
; 1: lift + target speed + vertical response (terms d0=vertical target).
; 2: height, with world contact block skipped (d2 low byte=was airborne).
; 3: corrected speed error (terms d0.w=error, d1.w=signed slew).
; 4: native speed response; field integrator may replace this operation.
; 5: coarse speed + horizontal coordinates/wind.
; 6: RPM target + response.
motion_stage_entries:
	dc.w $000,$116,$1fa,$2ba,$2e8,$2f6,$382
motion_stage_ends:
	dc.w $116,$1fa,$2ba,$2e8,$2f6,$382,$41c
