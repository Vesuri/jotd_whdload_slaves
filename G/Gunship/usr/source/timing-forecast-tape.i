; Bounded private player-forecast checkpoints. Foreground/serialized only.
; Disjoint buffers; caller owns simulation, allocation and dependency epochs.
; Context longs: lifecycle epoch (nonzero), world epoch, immutable stages,
; sine helper, ground clone, impulse policy. Epoch changes must cover modified
; code/data even when addresses are reused. This is NOT a scene/selector cache.
FCT_VALID equ 0
FCT_COUNT equ 2
FCT_CONTEXT equ 4
FCT_CONTEXT_SIZE equ 24
FCT_RESULT equ FCT_CONTEXT+FCT_CONTEXT_SIZE
FCT_RECORDS equ FCT_RESULT+MP_RECORD_SIZE
FCT_CAPACITY equ 20
FCT_SIZE equ FCT_RECORDS+FCT_CAPACITY*FC_SIZE

; a0=tape. Retire on lifecycle/context change, before reuse or freeing code.
forecast_tape_reset:
 clr.l (a0)
 clr.l FCT_CONTEXT(a0)
 moveq #0,d0
 rts

; a0=tape, a1=context. Begin invalidates old publication. Zero epoch rejects
; without writes. Caller appends initial and subsequent PRE-deadline states,
; then finishes with the separately resolved endpoint (including ground).
forecast_tape_begin:
 movem.l d1/a0-a1,-(sp)
 tst.l (a1)
 beq .bad
 clr.l (a0)
 adda.w #FCT_CONTEXT,a0
 moveq #FCT_CONTEXT_SIZE/4-1,d1
.copy:
 move.l (a1)+,(a0)+
 dbf d1,.copy
 moveq #0,d0
 bra .done
.bad:
 moveq #-3,d0
.done:
 movem.l (sp)+,d1/a0-a1
 rts

; a0=building tape, a1=owner, a2=player, a3=held packet.
; Consecutive field stamps and identical held directions are mandatory.
; Return 0/-3. Invalid/full/published tape leaves all storage unchanged.
forecast_tape_append:
 movem.l d1-d3/a0-a4,-(sp)
 tst.w FCT_VALID(a0)
 bne .bad
 tst.l FCT_CONTEXT(a0)
 beq .bad
 moveq #0,d1
 move.w FCT_COUNT(a0),d1
 cmpi.w #FCT_CAPACITY,d1
 bhs .bad
 tst.w d1
 beq .admitted
 move.l d1,d2
 subq.w #1,d2
 mulu.w #FC_SIZE,d2
 lea FCT_RECORDS(a0),a4
 adda.l d2,a4
 move.l EP_DELAY+CD_FIELD(a4),d3
 addq.l #1,d3
 cmp.l EP_DELAY+CD_FIELD(a1),d3
 bne .bad
 move.l (a3),d3
 cmp.l FC_CONTROL(a4),d3
 bne .bad
.admitted:
 mulu.w #FC_SIZE,d1
 lea FCT_RECORDS(a0),a4
 adda.l d1,a4
 moveq #EP_SIZE/4-1,d2
.owner:
 move.l (a1)+,(a4)+
 dbf d2,.owner
 IFNE EP_SIZE&2
 move.w (a1)+,(a4)+
 ENDC
 moveq #MP_RECORD_SIZE/4-1,d2
.player:
 move.l (a2)+,(a4)+
 dbf d2,.player
 IFNE MP_RECORD_SIZE&2
 move.w (a2)+,(a4)+
 ENDC
 move.l (a3),(a4)
 addq.w #1,FCT_COUNT(a0)
 moveq #0,d0
 bra .done
.bad:
 moveq #-3,d0
.done:
 movem.l (sp)+,d1-d3/a0-a4
 rts

; a0=building tape, a1=private final player. Publish only after all simulation
; succeeds. This function does not validate how the endpoint was calculated.
forecast_tape_finish:
 movem.l d1/a0-a1,-(sp)
 tst.w FCT_VALID(a0)
 bne .bad
 tst.l FCT_CONTEXT(a0)
 beq .bad
 move.w FCT_COUNT(a0),d1
 beq .bad
 cmpi.w #FCT_CAPACITY,d1
 bhi .bad
 move.l a0,-(sp)
 adda.w #FCT_RESULT,a0
 moveq #MP_RECORD_SIZE/4-1,d1
.copy:
 move.l (a1)+,(a0)+
 dbf d1,.copy
 IFNE MP_RECORD_SIZE&2
 move.w (a1)+,(a0)+
 ENDC
 movea.l (sp)+,a0
 move.w #1,FCT_VALID(a0)
 moveq #0,d0
 bra .done
.bad:
 moveq #-3,d0
.done:
 movem.l (sp)+,d1/a0-a1
 rts

; a0=published tape,a1=owner,a2=player,a3=held packet,a4=context,
; a5=private 86-byte output. Exact checkpoint+context hit returns endpoint/0.
; Miss returns -3 with output and tape unchanged. No native publication.
forecast_tape_lookup:
 movem.l d1-d3/a0-a6,-(sp)
 movea.l a0,a6
 move.l a5,d3
 cmpi.w #1,FCT_VALID(a6)
 bne .bad
 moveq #0,d2
 move.w FCT_COUNT(a6),d2
 beq .bad
 cmpi.w #FCT_CAPACITY,d2
 bhi .bad
 tst.l (a4)
 beq .bad
 lea FCT_CONTEXT(a6),a0
 moveq #FCT_CONTEXT_SIZE/4-1,d1
.context:
 cmpm.l (a0)+,(a4)+
 bne .bad
 dbf d1,.context
 move.l EP_DELAY+CD_FIELD(a1),d1
 sub.l FCT_RECORDS+EP_DELAY+CD_FIELD(a6),d1
 cmp.l d2,d1
 bhs .bad
 mulu.w #FC_SIZE,d1
 lea FCT_RECORDS(a6),a5
 adda.l d1,a5
 movea.l a1,a0
 movea.l a2,a1
 movea.l a5,a2
 bsr forecast_checkpoint_match
 tst.l d0
 bne .bad
 lea FCT_RESULT(a6),a0
 movea.l d3,a1
 moveq #MP_RECORD_SIZE/4-1,d1
.copy:
 move.l (a0)+,(a1)+
 dbf d1,.copy
 IFNE MP_RECORD_SIZE&2
 move.w (a0)+,(a1)+
 ENDC
 moveq #0,d0
 bra .done
.bad:
 moveq #-3,d0
.done:
 movem.l (sp)+,d1-d3/a0-a6
 rts
