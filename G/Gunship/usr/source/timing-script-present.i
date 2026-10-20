; Serialized world snapshot for renderer-only index-5 pose.
; Lifecycle owners invalidate SPC_VALID when resetting generation counters.
SPC_PLAYER equ 0
SPC_GENERATION equ 4
SPC_EXHAUSTED equ 8
SPC_TICK equ 10
SPC_PHASE equ 14
SPC_VALID equ 16
SPC_CURRENT equ 18 ; split XYZ, heading and both metadata bytes (9 bytes)
SPC_NEXT equ 28 ; packed XYZ words and heading byte
SPC_SIZE equ 36

; a0=SH,a1=prepared SP,a2=generation record,a3=P,a4=stable bitmap,
; a5=two palette bytes,d0=tick,d1=world phase0..2. Return 1/0, -3 bad phase.
script_present_capture:
 movem.l d1-d7/a0-a6,-(sp)
 cmpi.l #2,d1
 bhi .bad
 movea.l a0,a6
 clr.w SPC_VALID(a6)
 move.l a3,SPC_PLAYER(a6)
 move.l (a2),SPC_GENERATION(a6)
 move.w AG_EXHAUSTED(a2),SPC_EXHAUSTED(a6)
 move.l d0,SPC_TICK(a6)
 move.w d1,SPC_PHASE(a6)
 lea script_present_offsets(pc),a0
 lea SPC_CURRENT(a6),a2
 moveq #8,d2
.copy:
 move.w (a0)+,d3
 move.b 0(a3,d3.w),(a2)+
 dbf d2,.copy
 btst #0,SPC_EXHAUSTED+1(a6)
 bne .unknown
 movea.l a1,a0
 movea.l a3,a1
 movea.l a4,a2
 movea.l a5,a3
 bsr script_preview_forecast
 tst.l d0
 beq .done
 lea SP_PLAYER(a0),a1
 lea script_present_offsets(pc),a0
 lea SPC_NEXT(a6),a2
 moveq #6,d2
.next:
 move.w (a0)+,d3
 move.b 0(a1,d3.w),(a2)+
 dbf d2,.next
 move.w #1,SPC_VALID(a6)
 bra .done
.unknown:
 moveq #0,d0
 bra .done
.bad:
 moveq #-3,d0
.done:
 movem.l (sp)+,d1-d7/a0-a6
 rts

; a0=SH,a1=current generation record,a2=private seven-byte XYZ/heading output,
; a3=current P,d0=tick,d1=phase,d2=50/60. Invalid clock writes nothing.
; Return 1 predicted,0 committed,-3 invalid. Never reads bitmap pixels.
script_present_build:
 movem.l d1-d7/a0-a6,-(sp)
 cmpi.l #50,d2
 beq .rate
 cmpi.l #60,d2
 bne .bad
.rate:
 cmp.l d2,d1
 bhs .bad
 movea.l a0,a6
 movea.l a2,a4
 lea script_present_offsets(pc),a0
 moveq #6,d3
.seed:
 move.w (a0)+,d4
 move.b 0(a3,d4.w),(a2)+
 dbf d3,.seed
 cmpi.w #1,SPC_VALID(a6)
 bne .stale
 cmpa.l SPC_PLAYER(a6),a3
 bne .stale
 cmp.l SPC_TICK(a6),d0
 bne .stale
 move.l (a1),d0
 cmp.l SPC_GENERATION(a6),d0
 bne .stale
 move.w AG_EXHAUSTED(a1),d0
 or.w SPC_EXHAUSTED(a6),d0
 btst #0,d0
 bne .stale
 lea script_present_offsets(pc),a0
 lea SPC_CURRENT(a6),a2
 moveq #8,d3
.check:
 move.w (a0)+,d4
 move.b 0(a3,d4.w),d0
 cmp.b (a2)+,d0
 bne .stale
 dbf d3,.check
 sub.w SPC_PHASE(a6),d1
 bmi .stale
 move.l d1,d3
 divu.w #3,d3
 move.l d3,d4
 swap d4
 tst.w d4
 bne .stale
 andi.l #$ffff,d3
 sub.w SPC_PHASE(a6),d2
 addq.w #2,d2
 divu.w #3,d2
 andi.l #$ffff,d2
 lea SPC_CURRENT(a6),a0
 lea SPC_NEXT(a6),a1
 moveq #2,d4
.axis:
 move.w (a1)+,d0
 sub.w (a0),d0
 muls.w d3,d0
 divs.w d2,d0
 move.l d0,d1
 swap d1
 tst.w d1
 bpl .rounded
 subq.w #1,d0
.rounded:
 add.w (a0)+,d0
 move.w d0,(a4)+
 dbf d4,.axis
 ; Heading uses the shortest signed byte arc, including wrap at 255/0.
 move.b SPC_NEXT+6(a6),d0
 sub.b SPC_CURRENT+6(a6),d0
 ext.w d0
 muls.w d3,d0
 divs.w d2,d0
 move.l d0,d1
 swap d1
 tst.w d1
 bpl .heading_rounded
 subq.w #1,d0
.heading_rounded:
 add.b SPC_CURRENT+6(a6),d0
 move.b d0,(a4)
 moveq #1,d0
 bra .done
.stale:
 moveq #0,d0
 bra .done
.bad:
 moveq #-3,d0
.done:
 movem.l (sp)+,d1-d7/a0-a6
 rts
script_present_offsets:
 dc.w $5b,$d5,$db,$155,$255,$1d5,$15b,$1db,$25b
