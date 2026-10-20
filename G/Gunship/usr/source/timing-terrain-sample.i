; Read-only counterpart of native +0B3B2/+0825E/+082B6. The caller supplies
; a stable, DMA-complete committed BitMap and its two rejected palette bytes.
; No native bitmap binding, raster/OS calls, RNG or drawing. Not installed.
; a0=Amiga BitMap (row bytes, rows, flags, depth, pad, plane pointers),
; a1=two palette bytes, d0/d1=native incoming world-coordinate registers.
; Preserve the incoming HIGH half of d0: native word math then LSR.L uses it.
; Return d0=0/-1 classification, -3 unknown for out-of-bitmap coordinates,
; empty dimensions, unsupported depth or a null plane. Preserve other regs.
; Unlike the native access-fault patch, never read beyond a declared plane.
terrain_sample:
 movem.l d1-d7/a0-a3,-(sp)
 movea.l a1,a3
 ; Exact native world-to-map arithmetic, including word wrap and long shift.
 addi.w #128,d0
 addi.w #128,d1
 move.w d0,d2
 add.w d2,d2
 add.w d2,d0
 moveq #9,d2
 lsr.l d2,d0
 subi.w #20,d0
 lsr.w #8,d1
 subi.w #216,d1
 neg.w d1
 add.w d1,d1
 ext.l d0
 ext.l d1
 tst.l d0
 bmi .unknown
 tst.l d1
 bmi .unknown
 moveq #0,d2
 move.w (a0),d2
 beq .unknown
 move.l d2,d4
 lsl.l #3,d4
 cmp.l d4,d0
 bhs .unknown
 moveq #0,d4
 move.w 2(a0),d4
 cmp.l d4,d1
 bhs .unknown
 moveq #0,d3
 move.b 5(a0),d3
 beq .unknown
 cmpi.w #8,d3
 bhi .unknown
 ; Validate every plane before reading a single pixel.
 lea 8(a0),a1
 move.w d3,d4
 subq.w #1,d4
.planes:
 tst.l (a1)+
 beq .unknown
 dbf d4,.planes
 move.l d1,d5
 mulu.w d2,d5
 move.l d0,d4
 lsr.l #3,d4
 add.l d4,d5
 andi.w #7,d0
 eori.w #7,d0
 lea 8(a0),a1
 moveq #0,d6
 moveq #0,d7
 subq.w #1,d3
.pixel:
 movea.l (a1)+,a2
 adda.l d5,a2
 btst d0,(a2)
 beq .next
 bset d7,d6
.next:
 addq.w #1,d7
 dbf d3,.pixel
 cmp.b (a3),d6
 beq .blocked
 cmp.b 1(a3),d6
 beq .blocked
 moveq #0,d0
 bra .done
.blocked:
 moveq #-1,d0
 bra .done
.unknown:
 moveq #-3,d0
.done:
 movem.l (sp)+,d1-d7/a0-a3
 rts
