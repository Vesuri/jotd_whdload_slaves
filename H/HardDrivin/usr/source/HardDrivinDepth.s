; Road and objects in depth order (CUSTOM1 nonzero). The scene draw $FDD4
; fills the whole plain road ($FC1E) and then the objects far to near by their
; centre's depth, so a car beyond a crest, or behind the road climbing into the
; loop, was drawn over the road that hides it. The road needs no order of its
; own (a section hidden by a crest faces away and is culled), so its sections
; are sorted by their farthest corner and each object is drawn after the
; sections beyond its near side (its depth less its radius). Sections a
; structure draws with itself ($FA58, flags $F8) stay with the structure; the
; background and type-57 passes before the road are unchanged. A car more than
; 5 units under the ground ($FE40: in the stunt road's dip) was drawn before
; the road, which then covered it; it is drawn by depth with the other cars.
; A car beyond both roads' last strip points is not drawn: the road ends there
; on the screen, and the car stood on the grass beyond it.
DEPTH_MAX equ 255		; sections of both roads (each count is a byte)
DEPTH_REC equ 12		; far depth.w, colour.w, polygon.l, marking.l

_depth_patches:
	PL_START
	; PERF_RANGE VERIFY_RENDER $0fe40 $0032: cars under the ground with the others, by depth
	PL_S $fe40,$fe72-$fe40
	; PERF_RANGE VERIFY_RENDER $0fe72 $0006: record the plain road instead of drawing it
	PL_PS $fe72,_depth_collect
	; PERF_RANGE VERIFY_RENDER $0fe9e $0006: overhead objects after the road beyond them
	PL_PS $fe9e,_depth_object
	; PERF_RANGE VERIFY_RENDER $0fecc $0006: objects after the road beyond them
	PL_PS $fecc,_depth_object
	; PERF_RANGE VERIFY_RENDER $0ff36 $0006: the nearest road and the epilogue
	PL_P $ff36,_depth_tail
	PL_END

; Replaces JSR $FC1E; TST.W D5. Walks both roads' polygon streams as $FC1E
; does and records each drawn section; D5 and its flags are returned.
_depth_collect:
	movem.l d2-d7/a2-a3/a6,-(sp)
	lea _depth_recs(pc),a6
	moveq #0,d7			; records
	lea _depth_extent(pc),a1
	move.w #-$8000,(a1)
	lea -25276(a4),a0		; surface polygons, both roads
	movea.l -2168(a4),a1		; markings, road A
	movea.l -5786(a4),a2		; flags
	movea.l -5790(a4),a3		; strip points
	move.b -5782(a4),d5
	move.b -5775(a4),d6
	bsr .road
	movea.l -2164(a4),a1		; markings, road B
	movea.l -5774(a4),a2
	movea.l -5780(a4),a3
	move.b -5776(a4),d5
	move.b -5770(a4),d6
	bsr .road
	lea _depth_count(pc),a0
	move.w d7,(a0)+
	clr.w (a0)			; next
	bsr _depth_sort
	movem.l (sp)+,d2-d7/a2-a3/a6
	tst.w d5
	rts
; D5.b sections + 1, D6.b marked sections, A0/A1 streams, A2 flags, A3 strip.
.road:
	ext.w d5
	ext.w d6
	moveq #1,d4
	move.w d7,d3			; this road's first record
	bra .next
.section:
	move.w (a2)+,d0
	move.w (a0)+,d1			; surface vertices
	move.w d1,d2
	lsl.w #2,d2
	move.l a0,-(sp)
	adda.w d2,a0
	move.b d0,d2
	andi.b #$f8,d2
	beq.s .plain
	addq.l #4,sp			; a structure's or hidden: skip both
	move.w (a1)+,d1
	lsl.w #2,d1
	adda.w d1,a1
	bra.s .step
.plain:
	moveq #0,d2
	cmp.w d6,d4
	bgt.s .unmarked
	move.l a1,d2
	move.w (a1)+,d1
	lsl.w #2,d1
	adda.w d1,a1
.unmarked:
	cmpi.w #DEPTH_MAX,d7
	bhs.s .full
	move.w d7,d1
	mulu.w #DEPTH_REC,d1
	lea (a6,d1.l),a6
	; farthest corner: both edges of points I-1 and I
	move.w 4(a3),d1
	cmp.w 10(a3),d1
	bge.s .z1
	move.w 10(a3),d1
.z1:	cmp.w 16(a3),d1
	bge.s .z2
	move.w 16(a3),d1
.z2:	cmp.w 22(a3),d1
	bge.s .z3
	move.w 22(a3),d1
.z3:	move.w d1,(a6)+
	moveq #20,d1
	btst #0,d0
	beq.s .colour
	moveq #10,d1
.colour:
	move.w d1,(a6)+
	move.l (sp)+,(a6)+		; surface polygon, its count first
	subq.l #2,-4(a6)
	move.l d2,(a6)
	lea _depth_recs(pc),a6
	addq.w #1,d7
	bra.s .step
.full:
	addq.l #4,sp
.step:
	lea 12(a3),a3
	addq.w #1,d4
.next:
	cmp.w d5,d4
	blt .section
	; the road's extent: the farther end of its strip (it starts or ends
	; at the camera). A0 (the next road's polygons) is kept.
	cmpi.w #1,d5
	ble.s .extent_done
	lea _depth_extent(pc),a1
	move.w 4(a3),d1
	cmp.w 10(a3),d1
	bge.s .e1
	move.w 10(a3),d1
.e1:	cmp.w (a1),d1
	ble.s .e2
	move.w d1,(a1)
.e2:	move.w d5,d1
	subq.w #1,d1
	mulu.w #12,d1
	neg.l d1
	move.w 4(a3,d1.l),d2
	cmp.w 10(a3,d1.l),d2
	bge.s .e3
	move.w 10(a3,d1.l),d2
.e3:	cmp.w (a1),d2
	ble.s .extent_done
	move.w d2,(a1)
.extent_done:
	; the strip runs along the road, near to far or far to near: reverse it
	; to far to near, so the sort below has little to move
	move.w d7,d4
	subq.w #1,d4
	cmp.w d3,d4
	ble.s .done
	move.w d3,d1
	mulu.w #DEPTH_REC,d1
	lea (a6,d1.l),a2
	move.w d4,d1
	mulu.w #DEPTH_REC,d1
	lea (a6,d1.l),a3
	move.w (a2),d1
	cmp.w (a3),d1
	bge.s .done
.swap:
	movem.l (a2),d0-d2
	move.l (a3),(a2)+
	move.l 4(a3),(a2)+
	move.l 8(a3),(a2)+
	movem.l d0-d2,(a3)
	lea -DEPTH_REC(a3),a3
	cmpa.l a2,a3
	bhi.s .swap
.done:
	rts

; Insertion sort, far depth descending. Scratch D0-D4/A0-A3.
_depth_sort:
	lea _depth_recs(pc),a0
	move.w _depth_count(pc),d4
	subq.w #1,d4
	ble.s .done
	lea DEPTH_REC(a0),a1
.outer:
	movem.l (a1),d0-d2
	move.w (a1),d3
	movea.l a1,a2
.inner:
	cmpa.l a0,a2
	bls.s .place
	lea -DEPTH_REC(a2),a3
	cmp.w (a3),d3
	ble.s .place
	move.l (a3),(a2)
	move.l 4(a3),4(a2)
	move.l 8(a3),8(a2)
	movea.l a3,a2
	bra.s .inner
.place:
	movem.l d0-d2,(a2)
	lea DEPTH_REC(a1),a1
	subq.w #1,d4
	bne.s .outer
.done:
	rts

; Replaces MOVE.L A2,-(SP); MOVEA.L 36(A2),A0 before an object's draw.
; A2 object, A3 just past its list entry (its depth word at -6).
_depth_object:
	movem.l d0-d3/a0-a1,-(sp)
	move.w -6(a3),d0
	move.w 6(a2),d1			; radius
	moveq #20,d2
	and.b 28(a2),d2
	bne.s .far_key
	cmpi.b #111,25(a2)
	bne.s .near
.far_key:
	sub.w d1,d0			; the list's depth was its far side
.near:
	sub.w d1,d0
	move.w d0,-(sp)
	bsr.s _depth_flush
	move.w (sp)+,d2
	cmpi.b #8,28(a2)
	bne.s .draw
	cmp.w _depth_extent(pc),d2	; a car beyond the road's end
	ble.s .draw
	movem.l (sp)+,d0-d3/a0-a1
	movea.l (sp),a1
	move.l a2,(sp)
	lea _depth_none(pc),a0
	jmp (a1)
.draw:
	movem.l (sp)+,d0-d3/a0-a1
	movea.l (sp),a1
	move.l a2,(sp)
	movea.l 36(a2),a0
	jmp (a1)
_depth_none:
	rts

; Replaces MOVEM.L (SP)+,D4-D5/A2-A3; UNLK A5; RTS of $FDD4.
_depth_tail:
	move.w #-$8000,d0
	bsr.s _depth_flush
	lea _depth_count(pc),a0
	clr.l (a0)
	movem.l (sp)+,d4-d5/a2-a3
	unlk a5
	rts

; Draw the recorded sections farther than D0.w. Scratch D0-D3/A0-A1: the
; game's routines keep only D4-D7/A2-A6.
_depth_flush:
	movem.l d4-d5/a2,-(sp)
	move.w d0,d5
	lea _depth_count(pc),a2
	move.w (a2)+,d4
	sub.w (a2),d4			; left
	ble.s .done
	move.w (a2),d0
	mulu.w #DEPTH_REC,d0
	lea _depth_recs(pc),a2
	adda.l d0,a2
.loop:
	cmp.w (a2),d5
	bge.s .done
	move.w 2(a2),-(sp)
	jsr -32508(a4)			; colour
	addq.w #2,sp
	movea.l 4(a2),a0
	bsr.s .fill
	move.l 8(a2),d0
	beq.s .drawn
	move.w #5,-(sp)
	jsr -32508(a4)
	addq.w #2,sp
	movea.l 8(a2),a0
	bsr.s .fill
.drawn:
	lea _depth_next(pc),a0
	addq.w #1,(a0)
	lea DEPTH_REC(a2),a2
	subq.w #1,d4
	bne.s .loop
.done:
	movem.l (sp)+,d4-d5/a2
	rts
; A0 a polygon: count.w, then count X/Y longs.
.fill:
	move.w (a0)+,d0
	move.w d0,-(sp)
	lea -26562(a4),a1
	bra.s .copy_next
.copy:
	move.l (a0)+,(a1)+
.copy_next:
	dbf d0,.copy
	jsr -32502(a4)			; fill
	addq.w #2,sp
	rts

_depth_count: dc.w 0
_depth_next: dc.w 0
_depth_extent: dc.w 0		; the farther end of the roads' strips
_depth_recs: ds.b DEPTH_MAX*DEPTH_REC
	even
