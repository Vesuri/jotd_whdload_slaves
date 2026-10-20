; All three supported gamemule versions use the same blitter instruction sequences.
; Locate them in the loaded code hunk: offsets differ between releases. Validate
; the complete set before writing anything; unexpected layouts fail closed.
; The LoadSeg callback flushes caches after both these and the regular patches.

blitter_dispatch:
	movem.l d0-d7/a0-a6,-(sp)
	move.l _custom1(pc),d0
	beq .done
	lea pl_gamemule_658(pc),a3
	cmpa.l a3,a0
	beq .game
	lea pl_gamemule_1489(pc),a3
	cmpa.l a3,a0
	beq .game
	lea pl_gamemule_german(pc),a3
	cmpa.l a3,a0
	bne .done
.game:
	; LoadSeg allocation size includes its size word and next-segment BPTR.
	move.l -8(a1),d7
	cmpi.l #$9408,d7
	blo wrong_version
	cmpi.l #$20008,d7
	bhi wrong_version
	subi.l #32,d7 ; leave 24 bytes for the longest signature
	movea.l a1,a3
	lea blitter_sites(pc),a4
	moveq #0,d4 ; all wait loops
	moveq #0,d5 ; a1 loops
	moveq #0,d6 ; a6 loops
	suba.l a5,a5 ; pixel helper call, unique
.scan:
	move.w (a3),d0
	cmpi.w #$0828,d0 ; BTST #6,2(a0)
	beq .wait
	cmpi.w #$0829,d0 ; BTST #6,2(a1)
	beq .wait
	cmpi.w #$082e,d0 ; BTST #6,2(a6)
	bne .pixel
.wait:
	cmpi.l #$00060002,2(a3)
	bne .next
	cmpi.w #$66f8,6(a3) ; BNE.S back to BTST
	bne .next
	cmpi.w #14,d4
	bhs wrong_version
	move.l a3,(a4)+
	addq.w #1,d4
	cmpi.w #$0829,d0
	bne .not_a1
	addq.w #1,d5
.not_a1:
	cmpi.w #$082e,d0
	bne .next
	addq.w #1,d6
	bra .next
.pixel:
	; MOVEM d2-d6/a0-a1,-(sp); JSR coordinate helper;
	; MOVE.B colour,D6; MOVEA.L (A1),A0; ADDA.L D5,A0; BTST D3,D6.
	cmpi.l #$48e73ec0,(a3)
	bne .next
	cmpi.w #$4eb9,4(a3)
	bne .next
	lea $2c(a3),a0
	cmpa.l 6(a3),a0
	bne .next
	cmpi.w #$1c39,10(a3)
	bne .next
	cmpi.l #$2051d1c5,16(a3)
	bne .next
	cmpi.w #$0706,20(a3)
	bne .next
	move.l a5,d0
	bne wrong_version
	lea 4(a3),a5
.next:
	addq.l #2,a3
	subq.l #2,d7
	bpl .scan
	cmpi.w #14,d4
	bne wrong_version
	cmpi.w #1,d5
	bne wrong_version
	cmpi.w #1,d6
	bne wrong_version
	move.l a5,d0
	beq wrong_version

	; No game instruction has been changed until every signature passes.
	lea blitter_pixel_target(pc),a0
	move.l 2(a5),(a0)
	lea blitter_pixel(pc),a0
	move.l a0,2(a5)
	lea blitter_sites(pc),a4
	lea blitter_wait(pc),a0
	moveq #13,d0
.patch:
	movea.l (a4)+,a3
	move.w #$4eb9,(a3)
	move.l a0,2(a3)
	move.w #$4e71,6(a3)
	dbf d0,.patch
.done:
	movem.l (sp)+,d0-d7/a0-a6
	rts

; The first read allows a just-started blit to assert BBUSY. BTST changes
; only Z, matching the original loop; all registers and X/N/V/C survive.
blitter_wait:
	btst #6,$dff002
.busy:
	btst #6,$dff002
	bne .busy
	rts

; Called in place of the pixel plotter's coordinate helper. Its arguments
; are in registers. The original helper overwrites CCR before returning.
blitter_pixel:
	bsr blitter_wait
	move.l blitter_pixel_target(pc),-(sp)
	rts

blitter_pixel_target: dc.l 0
blitter_sites: ds.l 14
