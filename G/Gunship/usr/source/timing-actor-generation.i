; Allocation generations for the six shared projectile/effect slots.
AG_GENERATIONS equ 0 ; six unsigned longwords, zero at lifecycle activation
AG_EXHAUSTED equ 24 ; sticky slot bits; never predict a slot after overflow
AG_SIZE equ 26

; a0=AG state, d0=native allocation result (slot+1, or zero on failure).
; Preserve all registers; CCR unspecified. Invalid/failure inputs do nothing.
; Generation zero names the initial epoch occupant, if any. Future prediction
; resets its cached identities whenever lifecycle activation clears this state.
actor_generation_record:
 movem.l d0-d2/a0-a1,-(sp)
 tst.l d0
 beq .done
 cmpi.l #6,d0
 bhi .done
 subq.w #1,d0
 move.w AG_EXHAUSTED(a0),d2
 btst d0,d2
 bne .done
 move.w d0,d1
 lsl.w #2,d1
 lea AG_GENERATIONS(a0),a1
 adda.w d1,a1
 cmpi.l #-1,(a1)
 beq .exhausted
 addq.l #1,(a1)
 bra .done
.exhausted:
 bset d0,d2
 move.w d2,AG_EXHAUSTED(a0)
.done:
 movem.l (sp)+,d0-d2/a0-a1
 rts
