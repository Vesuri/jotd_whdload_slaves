; Enabled only by VERIFY_C_ROAD_TIMING; see simulation-timing.md.
; Diagnostic road normalization: evaluate the four-field reference,
; retaining quarter-unit output while running the simulation every field.
step_road_fraction: dc.l 0
step_road_history: dc.w 0,0,0,0
step_road_reference:
 movem.l d0/d2/a0,-(a7)
 move.l $26(a1),d1
 lsl.l #2,d1
 lsr.l #8,d1
 lea step_road_history(pc),a0
 move.w d6,d0
 add.w (a0),d0
 add.w 2(a0),d0
 add.w 4(a0),d0
 move.w 2(a0),4(a0)
 move.w (a0),2(a0)
 move.w d6,(a0)
 muls.w d0,d1
 asr.l #8,d1
 muls.w #768,d1
 asr.l #8,d1
 lea step_road_fraction(pc),a0
 add.l (a0),d1
 move.l d1,d0
 bpl .positive
 neg.l d0
.positive:
 move.l d0,d2
 andi.l #3,d2
 lsr.l #2,d0
 tst.l d1
 bpl .store
 neg.l d0
 neg.l d2
.store:
 move.l d2,(a0)
 move.l d0,d1
 add.w d1,$36(a1)
 movem.l (a7)+,d0/d2/a0
 jmp $8bad2

; Normalize native per-call NPC road-centre accumulation.
step_actor_road:
 movem.l d0/d2/a0,-(a7)
 move.l a1,d0
 subi.l #$a5d60,d0
 cmpi.l #$1180,d0
 bcc .native
 lsr.l #5,d0
 lea step_actor_road_fraction(pc),a0
 adda.l d0,a0
 move.w d1,d0
 ext.l d0
 add.l (a0),d0
 move.l d0,d2
 asr.l #2,d0
 add.w d0,$36(a1)
 andi.l #3,d2
 move.l d2,(a0)
 bra .done
.native:
 add.w d1,$36(a1)
.done:
 movem.l (a7)+,d0/d2/a0
 move.b (a4)+,d1
 rts
 cnop 0,4
step_actor_road_fraction: ds.l 35

; Keep external fractional road position with native companion record copies.
step_actor_road_copy:
 movem.l d0-d2/a2,-(a7)
 move.l a0,d0
 subi.l #$a5d60,d0
 cmpi.l #$1180,d0
 bcc .done
 move.l d0,d2
 andi.l #$7f,d2
 bne .done
 lsr.l #5,d0
 lea step_actor_road_fraction(pc),a2
 adda.l d0,a2
 move.l a1,d1
 subi.l #$a5d60,d1
 cmpi.l #$1180,d1
 bcc .clear
 move.l d1,d2
 andi.l #$7f,d2
 bne .clear
 lsr.l #5,d1
 sub.l d0,d1
 move.l (a2,d1.w),(a2)
 bra .done
.clear:
 clr.l (a2)
.done:
 movem.l (a7)+,d0-d2/a2
 lsr.w $2c(a0)
 move.w #1,$8b484
 rts
