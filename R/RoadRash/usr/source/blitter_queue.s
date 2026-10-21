; E1/E2: bounded background descriptor ring, owned only while drawing the road.
; Installed in the relocated main image (CUSTOM2 + public allocation required).
; Native 68000 and callers with masked/owned BLIT interrupts stay synchronous.
e_blitter_init:
 ; The hill copy must finish before its registers are reused for the cutout.
 move.l a5,a1
 adda.l #$32f8e,a1
 lea e_hill_wait(pc),a0
 move.w #$4eb9,(a1)
 move.l a0,2(a1)
 IFD VERIFY_E_CONTROL
 bra.w .done
 ELSE
 nop
 nop
 ENDC
 btst #1,verify_attn+3(pc)
 beq .done
 lea e_main(pc),a0
 move.l a5,(a0)
 move.l a5,a1
 adda.l #$2fd60,a1
 lea e_background_road(pc),a0
 move.w #$4eb9,(a1)
 move.l a0,2(a1)
 move.w #$4e71,6(a1)
.done:
 rts

e_background_road:
 movem.l d0-d7/a0-a6,-(a7)
 move.l e_main(pc),a2
 adda.l #$2726e,a2
 move.l (a2),a2
 move.w (a2),d6
 subi.w #16,d6
 ; Outside the ordinary horizon range retain the exact native edge cases.
 cmpi.w #135,d6
 bhi .native
 move.w sr,d0
 andi.w #$0700,d0
 cmpi.w #$0300,d0
 bcc .native
 lea $dff000,a0
 move.w $1c(a0),d0
 andi.w #$0070,d0
 bne .native
 bsr e_blitter_wait
 lea e_ring(pc),a1
 move.l $408.w,d2
 addi.l #$6270,d2
 move.w d6,d3
 lsl.w #6,d3
 ori.w #20,d3
 moveq #3,d4
.sky:
 move.l d2,(a1)+
 move.w #$0100,(a1)+ ; constant fill needs only the destination channel
 move.w d3,(a1)+
 subi.l #$20d0,d2
 dbf d4,.sky
 move.l $408.w,d2
 addi.l #$41a0,d2
 moveq #42,d0
 mulu.w d6,d0
 add.l d0,d2
 move.w #136,d3
 sub.w d6,d3
 lsl.w #6,d3
 ori.w #20,d3
 move.l d2,(a1)+
 move.w #$01ff,(a1)+
 move.w d3,(a1)+
 addi.l #$20d0,d2
 move.l d2,(a1)+
 move.w #$01ff,(a1)+
 move.w d3,(a1)+
 lea e_read(pc),a1
 clr.w (a1)
 ; A zero-height sky is omitted, never encoded as a 1024-line blit.
 tst.w d6
 bne .install
 move.w #32,(a1)
.install:
 move.w sr,-(a7)
 ori.w #$0700,sr
 lea e_old_vector(pc),a1
 move.l $6c.w,(a1)
 lea e_irq(pc),a1
 move.l a1,$6c.w
 move.w $2(a0),d0
 andi.w #$0400,d0
 lea e_priority(pc),a1
 move.w d0,(a1)
 move.w #$0400,$96(a0)
 move.w #$0040,$9c(a0)
 move.w #$0040,$9c(a0)
 move.w #$8040,$9a(a0)
 bsr e_start_next
 move.w (a7)+,sr
 movem.l (a7)+,d0-d7/a0-a6
 bsr e_draw_road
 movem.l d0-d2/a0-a1,-(a7)
 lea $dff000,a0
.drain:
 move.w e_active(pc),d0
 bne .drain
 move.w sr,-(a7)
 ori.w #$0700,sr
 move.w #$0040,$9a(a0)
 move.w #$0040,$9c(a0)
 move.w #$0040,$9c(a0)
 move.l e_old_vector(pc),$6c.w
 move.w e_priority(pc),d0
 beq .restored
 move.w #$8400,$96(a0)
.restored:
 move.w (a7)+,sr
 movem.l (a7)+,d0-d2/a0-a1
 rts
.native:
 movem.l (a7)+,d0-d7/a0-a6
 move.l e_main(pc),a0
 adda.l #$31744,a0
 jsr (a0)
e_draw_road:
 move.l e_main(pc),a0
 adda.l #$310d0,a0
 jmp (a0)

e_blitter_wait:
 btst #6,2(a0)
.wait:
 btst #6,2(a0)
 bne .wait
 rts

e_irq:
 movem.l d0-d1/a0-a1,-(a7)
 lea $dff000,a0
 move.w $1e(a0),d0
 and.w $1c(a0),d0
 btst #6,d0
 beq .chain
 move.w #$0040,$9c(a0)
 move.w #$0040,$9c(a0)
 bsr e_start_next
.chain:
 movem.l (a7)+,d0-d1/a0-a1
 rte

e_start_next:
 lea e_read(pc),a1
 move.w (a1),d0
 cmpi.w #48,d0
 beq .empty
 addq.w #8,(a1)
 lea e_active(pc),a1
 move.w #1,(a1)
 lea e_ring(pc),a1
 adda.w d0,a1
 move.l (a1)+,$54(a0)
 move.w (a1)+,$40(a0)
 clr.w $42(a0)
 move.l #$ffffffff,$44(a0)
 move.w #2,$66(a0)
 move.w (a1)+,$58(a0)
 rts
.empty:
 lea e_active(pc),a1
 clr.w (a1)
 rts

e_main: dc.l 0
e_old_vector: dc.l 0
e_priority: dc.w 0
e_read: dc.w 0
e_active: dc.w 0
e_ring: dcb.b 48,0
 even

; Native $b2f8e starts programming the cutout immediately after BLTSIZE.
; BLTPRI used to hide the missing wait by stalling the following Chip fetch.
e_hill_wait:
 btst #6,2(a3)
.wait:
 btst #6,2(a3)
 bne .wait
 addq.l #2,a0
 andi.w #$ffc0,d7
 rts
