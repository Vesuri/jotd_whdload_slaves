; Exact checkpoint admission for a privately simulated held-control tail.
; This matches evidence only; it does not compute, publish or cache a pose.
FC_PLAYER equ EP_SIZE
FC_CONTROL equ FC_PLAYER+MP_RECORD_SIZE
FC_SIZE equ FC_CONTROL+4

; a0=current endpoint owner, a1=current player, a2=FC_SIZE checkpoint,
; a3=current immutable input packet (first two signed direction words).
; Return 0 exact match, -3 mismatch. Preserve other registers; no writes.
; Owner includes field stamp, interval tick/span/progress, fractions and
; delayed controls. Compare the ENTIRE player, including command-owned bytes.
; Caller must separately validate lifecycle/code epoch and forecast context,
; and must never use this as a shared-world/visibility certificate. A checkpoint
; is valid only for the same prepared immutable motion/ground code and a tail
; constructed with the compared held directions and its stated impulse policy.
forecast_checkpoint_match:
 movem.l d1-d2/a0-a3,-(sp)
 moveq #EP_SIZE/4-1,d2
.owner:
 cmpm.l (a0)+,(a2)+
 bne .different
 dbf d2,.owner
 IFNE EP_SIZE&2
 cmpm.w (a0)+,(a2)+
 bne .different
 ENDC
 moveq #MP_RECORD_SIZE/4-1,d2
.player:
 cmpm.l (a1)+,(a2)+
 bne .different
 dbf d2,.player
 IFNE MP_RECORD_SIZE&2
 cmpm.w (a1)+,(a2)+
 bne .different
 ENDC
 move.l (a3),d1
 cmp.l (a2),d1
 bne .different
 moveq #0,d0
 bra .done
.different:
 moveq #-3,d0
.done:
 movem.l (sp)+,d1-d2/a0-a3
 rts
