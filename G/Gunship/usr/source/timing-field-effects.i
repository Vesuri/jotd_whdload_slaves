; Once per consumed field, before world constructors/slot lifetime work.
; a0=effect slot table (hunk 0+$c6d0), preserve all registers except flags.
; Replays native VBL byte wrap, then +be5a animation, without drawing/RNG.
; The native VBL and renderer owners must both be excluded during replay.
field_effects_step:
 movem.l d0-d2/a0-a1,-(sp)
 lea $54(a0),a1
 moveq #5,d2
.countdown:
 subq.b #1,0(a1,d2.w)
 dbf d2,.countdown
 moveq #5,d2
.animate:
 btst #0,6(a0,d2.w)
 beq .next
 move.b 12(a0,d2.w),d1
 tst.b 0(a1,d2.w)
 bpl .frame
 move.b #8,0(a1,d2.w)
 addq.b #1,d1
.frame:
 cmpi.b #6,d1
 blt .store
 move.b #1,0(a0,d2.w)
 move.b #6,12(a0,d2.w)
 bra .next
.store:
 move.b d1,12(a0,d2.w)
.next:
 dbf d2,.animate
 movem.l (sp)+,d0-d2/a0-a1
 rts
