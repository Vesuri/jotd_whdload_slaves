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
	; PERF_RANGE VERIFY_RENDER $09ae4 $0008: keep each car's centre in camera space
	PL_P $9ae4,_occ_centre
	PL_END

; Replaces JSR $FC1E; TST.W D5. Walks both roads' polygon streams as $FC1E
; does and records each drawn section; D5 and its flags are returned.
_depth_collect:
	movem.l d2-d7/a2-a3/a6,-(sp)
	lea _depth_recs(pc),a6
	moveq #0,d7			; records
	lea _depth_extent(pc),a1
	move.w #-$8000,(a1)
	lea _occ_nsolid(pc),a1
	clr.w (a1)
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
	bne.s .solid
	cmp.w _depth_extent(pc),d2	; a car beyond the road's end
	ble.s .car
	lea _depth_none(pc),a0
	bra.s .call
.car:
	lea _occ_car(pc),a0		; drawn, then the faces in front of it
	bra.s .call
.solid:
	lea OCC_FACES(a4),a0		; faces with planes ($F792): kept
	cmpa.l 36(a2),a0
	bne.s .draw
	lea _occ_nsolid(pc),a0
	move.w (a0),d0
	cmpi.w #OCC_SOLIDS,d0
	bhs.s .draw
	addq.w #1,(a0)+
	lsl.w #2,d0
	move.l a2,(a0,d0.w)
.draw:
	movea.l 36(a2),a0
.call:
	lea 24(sp),sp			; D0-D3/A0-A1: scratch for the draw
	movea.l (sp),a1
	move.l a2,(sp)
	jmp (a1)
_depth_none:
	rts

; Replaces MOVEM.L (SP)+,D4-D5/A2-A3; UNLK A5; RTS of $FDD4.
_depth_tail:
	move.w #-$8000,d0
	bsr.s _depth_flush
	lea _depth_count(pc),a0
	clr.l (a0)
	lea _occ_ncar(pc),a0
	clr.w (a0)
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

; Cars behind a solid's faces. A solid (an object drawn by $F792, classes 4
; and 16: barns, the stunt road's raised forks) is drawn at its far side and
; the cars nearer than that after it, so a car behind its slopes was drawn on
; them. After each car, every face of the solids drawn before it that has the
; car's centre behind its plane, the camera in front, is filled again inside
; the car's box on the screen.
OCC_FACES equ -32274		; the jump-table entry of $F792
OCC_SOLIDS equ 8
OCC_CARS equ 16
OCC_CAR equ 10			; object.l, centre X/Y/Z
OCC_NEAR equ 32			; a car nearer than this is not tested

; Replaces MOVEM.L (SP)+,D4-D7/A2-A3; UNLK A5; RTS at the end of $97DC, an
; object's transform, where D5-D7 are its origin in camera space.
_occ_centre:
	movem.l d0/a0-a1,-(sp)
	movea.l 8(a5),a0
	cmpi.b #8,28(a0)
	bne.s .done
	lea _occ_ncar(pc),a1
	move.w (a1),d0
	cmpi.w #OCC_CARS,d0
	bhs.s .done
	addq.w #1,(a1)+
	mulu.w #OCC_CAR,d0
	adda.w d0,a1
	move.l a0,(a1)+
	move.w d5,(a1)+
	move.w d6,(a1)+
	move.w d7,(a1)
.done:
	movem.l (sp)+,d0/a0-a1
	movem.l (sp)+,d4-d7/a2-a3
	unlk a5
	rts

; A car's draw, called as its routine (the object at 4(SP)), then the faces
; in front of it. D0-D3/A0-A1 are scratch.
_occ_car:
	movea.l 4(sp),a0
	move.l a0,-(sp)
	movea.l 36(a0),a0
	jsr (a0)
	addq.l #4,sp
	move.w _occ_nsolid(pc),d0
	bne.s .test
	rts
.test:
	movem.l d4-d7/a2-a3/a5-a6,-(sp)
	movea.l 32+4(sp),a2		; the car
	tst.b 34(a2)			; clipped at the camera: near, left
	bne .out
	lea _occ_ncar(pc),a0
	move.w (a0)+,d0
	bra.s .find_next
.find:
	cmpa.l (a0),a2
	beq.s .found
	lea OCC_CAR(a0),a0
.find_next:
	dbf d0,.find
	bra .out
.found:
	movem.w 4(a0),d5-d7		; centre X, Y, Z (Z ahead)
	cmpi.w #OCC_NEAR,d7
	blt .out
	; its box: X 256 x/z, Y -256 y/z, half 256 r/z
	move.l d5,d0
	asl.l #8,d0
	divs.w d7,d0
	bvs .out
	move.l d6,d1
	asl.l #8,d1
	divs.w d7,d1
	bvs .out
	neg.w d1
	moveq #0,d2
	move.w 6(a2),d2
	asl.l #8,d2
	divu.w d7,d2
	bvs .out
	addq.w #2,d2
	move.l -27124(a4),-(sp)		; Y top and bottom
	move.l -27120(a4),-(sp)		; X right and left
	move.w d1,d3
	add.w d2,d3
	cmp.w -27124(a4),d3
	bge.s .y1
	move.w d3,-27124(a4)
.y1:	sub.w d2,d1
	cmp.w -27122(a4),d1
	ble.s .y0
	move.w d1,-27122(a4)
.y0:	move.w d0,d3
	add.w d2,d3
	cmp.w -27120(a4),d3
	bge.s .x1
	move.w d3,-27120(a4)
.x1:	sub.w d2,d0
	cmp.w -27118(a4),d0
	ble.s .x0
	move.w d0,-27118(a4)
.x0:	move.w -27124(a4),d0
	cmp.w -27122(a4),d0
	blt.s .restore
	move.w -27120(a4),d0
	cmp.w -27118(a4),d0
	blt.s .restore
	lea _occ_nsolid(pc),a3
	move.w (a3)+,d4
	bra.s .solid_next
.solid:
	movea.l (a3)+,a2
	bsr.s _occ_solid
.solid_next:
	dbf d4,.solid
.restore:
	move.l (sp)+,-27120(a4)
	move.l (sp)+,-27124(a4)
.out:
	movem.l (sp)+,d4-d7/a2-a3/a5-a6
	rts

; A2 a solid, D5-D7 the car's centre. Each face is n.b, plane.b, n vertex
; indices, colour.b; the plane and the first vertex are rotated points (the
; plane through the origin), so with A the plane dotted with the vertex and
; B with the centre less A, the face is towards the camera when A < 0 (the
; native test, $2BDE) and the car behind it when B < 0. Clipped at the camera
; (34 set), $A194 left a polygon for each face (n.w, colour.w, points; n 0
; when it is culled) and the plane test alone decides.
_occ_solid:
	move.w d4,-(sp)
	movea.l 52(a2),a5		; faces
	movea.l 44(a2),a6		; rotated points
	moveq #0,d3
	move.b 23(a2),d3
	movea.l 48(a2),a1		; screen points, or the polygons
	bra .next
.face:
	moveq #0,d0
	move.b (a5)+,d0			; n
	move.w d0,-(sp)
	moveq #0,d1
	move.b (a5)+,d1			; plane
	mulu.w #6,d1
	movem.w (a6,d1.w),d0-d1/a0	; the plane (A0 as a word)
	; ground (Y over twice X and Z): the road is drawn over it, and a
	; car in a cutting below it
	move.w d1,d2
	bpl.s .y
	neg.w d2
.y:	move.w d0,d4
	bpl.s .x
	neg.w d4
.x:	add.w d4,d4
	cmp.w d2,d4
	bhi.s .steep
	move.w a0,d4
	bpl.s .z
	neg.w d4
.z:	add.w d4,d4
	cmp.w d2,d4
	bls .skip
.steep:
	moveq #0,d2
	move.b (a5),d2			; the first vertex
	mulu.w #6,d2
	move.w d0,-(sp)
	muls.w (a6,d2.w),d0
	move.w d1,-(sp)
	muls.w 2(a6,d2.w),d1
	add.l d1,d0
	move.w a0,d1
	muls.w 4(a6,d2.w),d1
	add.l d1,d0			; A
	move.w (sp)+,d1
	muls.w d6,d1
	move.w (sp)+,d2
	muls.w d5,d2
	add.l d2,d1
	move.w a0,d2
	muls.w d7,d2
	add.l d2,d1
	sub.l d0,d1			; B
	tst.b 34(a2)
	bne.s .clipped
	tst.l d0
	bpl.s .skip			; culled
	tst.l d1
	bpl.s .skip			; the car is in front
	; fill the face again from its screen points
	move.w (sp),d2
	lea -26562(a4),a0
	bra.s .copy_next
.copy:
	moveq #0,d0
	move.b (a5)+,d0
	lsl.w #2,d0
	move.l (a1,d0.w),(a0)+
.copy_next:
	dbf d2,.copy
	moveq #0,d0
	move.b (a5)+,d0
	move.l a1,-(sp)			; the calls keep D1-D7/A2-A6
	move.w d0,-(sp)
	jsr -32508(a4)			; colour
	addq.w #2,sp
	move.w 4(sp),-(sp)		; n
	jsr -32502(a4)			; fill
	addq.w #2,sp
	movea.l (sp)+,a1
	addq.w #2,sp
	bra.s .next
.skip:
	move.w (sp)+,d0
	lea 1(a5,d0.w),a5		; the indices and the colour
	tst.b 34(a2)
	beq.s .next
	bra.s .poly_skip
.clipped:
	; the polygon for this face
	move.w (a1),d2			; its count, 0 if not drawn
	beq.s .skip
	eor.l d0,d1			; A and B the same sign: behind
	bmi.s .skip
	tst.l d0
	beq.s .skip
	move.w (sp)+,d0
	lea 1(a5,d0.w),a5
	move.w (a1)+,d2			; count
	move.w (a1)+,d0			; colour
	move.w d2,d1
	lea -26562(a4),a0
	bra.s .pcopy_next
.pcopy:
	move.l (a1)+,(a0)+
.pcopy_next:
	dbf d1,.pcopy
	move.l a1,-(sp)
	move.w d0,-(sp)
	jsr -32508(a4)
	addq.w #2,sp
	move.w d2,-(sp)
	jsr -32502(a4)
	addq.w #2,sp
	movea.l (sp)+,a1
	bra.s .next
.poly_skip:
	move.w (a1)+,d0
	addq.l #2,a1
	lsl.w #2,d0
	adda.w d0,a1
.next:
	dbf d3,.face
	move.w (sp)+,d4
	rts

_occ_nsolid: dc.w 0
_occ_solids: ds.l OCC_SOLIDS
_occ_ncar: dc.w 0
_occ_cars: ds.b OCC_CARS*OCC_CAR
	even

_depth_count: dc.w 0
_depth_next: dc.w 0
_depth_extent: dc.w 0		; the farther end of the roads' strips
_depth_recs: ds.b DEPTH_MAX*DEPTH_REC
	even
