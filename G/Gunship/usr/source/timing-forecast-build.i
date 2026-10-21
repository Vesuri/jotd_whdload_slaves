; Private held-control endpoint forecast. No publication to native state.
; Disjoint, word-aligned buffers; prepared code and dependencies stay immutable.
FB_TAPE equ 0
FB_CONTEXT equ 4
FB_EVENT equ 8
FB_OWNER equ 12
FB_PLAYER equ FB_OWNER+EP_SIZE
FB_PACKET equ FB_PLAYER+MP_RECORD_SIZE
FB_CACHE equ FB_PACKET+PS_INPUT_SIZE
FB_SIZE equ FB_CACHE+PC_SIZE

; a0=tape, a1=active EP owner, a2=player, a3=held directions (4 bytes),
; a4=context, a5=FB_SIZE scratch, d0=empty event bound to context's ground clone.
; Context impulse policy must be zero: forecast no future random impulses.
; Caller begins a new interval before calling when the previous one completed.
; Return 0 or -3; preserve all other registers. Retire tape even on rejection.
; Source owner/player/controls/context are immutable. Scratch and private event
; may change on failure, but no partial tape becomes visible. Event is NEVER
; committed by this routine. Caller retires/discards it before subsequent use.
forecast_player_build:
 movem.l d1-d7/a0-a6,-(sp)
 movea.l a5,a6
 move.l a0,FB_TAPE(a6)
 move.l a4,FB_CONTEXT(a6)
 move.l d0,FB_EVENT(a6)
 bsr forecast_tape_reset
 movea.l FB_EVENT(a6),a5
 tst.l (a5)
 bne .bad
 tst.l 20(a4)
 bne .bad
 moveq #0,d1
 move.w EP_SPAN(a1),d1
 sub.w EP_DONE(a1),d1
 bls .bad
 cmpi.w #FCT_CAPACITY,d1
 bhi .bad
 ; Per-construction cache: no prepared-code lifetime may cross this reset.
 clr.w FB_CACHE+PC_VALID(a6)
 lea FB_OWNER(a6),a5
 moveq #EP_SIZE/2-1,d2
.owner:
 move.w (a1)+,(a5)+
 dbf d2,.owner
 moveq #MP_RECORD_SIZE/2-1,d2
.player:
 move.w (a2)+,(a5)+
 dbf d2,.player
 move.l (a3),(a5)+
 clr.l (a5)+
 clr.w (a5)
 movea.l a4,a1
 bsr forecast_tape_begin
 tst.l d0
 bne .bad
.next:
 movea.l FB_TAPE(a6),a0
 lea FB_OWNER(a6),a1
 lea FB_PLAYER(a6),a2
 lea FB_PACKET(a6),a3
 bsr forecast_tape_append
 tst.l d0
 bne .bad
 lea FB_OWNER(a6),a0
 lea FB_PLAYER(a6),a1
 movea.l FB_CONTEXT(a6),a5
 movea.l 8(a5),a2
 movea.l 12(a5),a3
 lea FB_PACKET(a6),a4
 move.l EP_DELAY+CD_FIELD(a0),d0
 addq.l #1,d0
 lea FB_CACHE(a6),a5
 bsr endpoint_player_step_cached
 tst.l d0
 bne .bad
 subq.w #1,d1
 bne .next
 movea.l FB_CONTEXT(a6),a5
 movea.l 16(a5),a3
 movea.l FB_EVENT(a6),a4
 bsr endpoint_ground_resolve
 tst.l d0
 bmi .bad
 movea.l FB_TAPE(a6),a0
 lea FB_PLAYER(a6),a1
 bsr forecast_tape_finish
 tst.l d0
 bne .bad
 bra .done
.bad:
 movea.l FB_TAPE(a6),a0
 bsr forecast_tape_reset
 moveq #-3,d0
.done:
 movem.l (sp)+,d1-d7/a0-a6
 rts

; Same inputs as forecast_player_build, plus a6=private 86-byte output.
; Return 0 cached, 1 rebuilt, -3 rejected. Output changes only on success.
; Exact checkpoint/context lookup precedes construction. A hit does not touch
; scratch or event. A miss requires an empty private event as for the builder.
; No world/scene certificate is implied by a successful player forecast.
forecast_player_get:
 movem.l d1-d7/a0-a6,-(sp)
 move.l d0,-(sp)
 move.l a5,-(sp)
 movea.l a6,a5
 bsr forecast_tape_lookup
 movea.l (sp)+,a5
 tst.l d0
 beq .hit
 move.l (sp),d0
 bsr forecast_player_build
 tst.l d0
 bne .done
 movea.l a6,a5
 bsr forecast_tape_lookup
 tst.l d0
 bne .done
 moveq #1,d0
 bra .done
.hit:
 moveq #0,d0
.done:
 addq.l #4,sp
 movem.l (sp)+,d1-d7/a0-a6
 rts
