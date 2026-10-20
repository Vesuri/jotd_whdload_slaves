; Native periodic flight-end check and reserve depletion. Not installed.
; All copied branches stay within their blocks; neither block has relocations.
RS_GUARD_SIZE equ $24         ; +07f80..+07fa4, includes RTS
RS_RESERVE_SIZE equ $7e       ; +0590c..+0598a
RS_CODE_SIZE equ RS_GUARD_SIZE+RS_RESERVE_SIZE+2

; a0=0658 hunk 0, a1=even clone. Return 0/-1, preserve other registers.
; Validate every instruction before writing. Nonoverlapping buffers required;
; flush instruction caches before using the clone.
world_reserves_prepare:
	movem.l d1/a0/a2-a4,-(sp)
	lea $7f80(a0),a2
	lea .guard(pc),a3
	moveq #RS_GUARD_SIZE/2-1,d1
.guard_check:
	cmpm.w (a2)+,(a3)+
	bne .bad
	dbf d1,.guard_check
	lea $590c(a0),a2
	lea .reserves(pc),a3
	moveq #RS_RESERVE_SIZE/2-1,d1
.reserve_check:
	cmpm.w (a2)+,(a3)+
	bne .bad
	dbf d1,.reserve_check
	movea.l a1,a4
	lea $7f80(a0),a2
	moveq #RS_GUARD_SIZE/2-1,d1
.guard_copy:
	move.w (a2)+,(a4)+
	dbf d1,.guard_copy
	lea $590c(a0),a2
	moveq #RS_RESERVE_SIZE/2-1,d1
.reserve_copy:
	move.w (a2)+,(a4)+
	dbf d1,.reserve_copy
	move.w #$4e75,(a4)
	moveq #0,d0
	bra .done
.bad:
	moveq #-1,d0
.done:
	movem.l (sp)+,d1/a0/a2-a4
	rts
.guard:
	dc.w $102d,$0042,$0200,$000c,$6618,$0c2d,$0020,$001b
	dc.w $6410,$4a6d,$001c,$660a,$102d,$0052,$6704,$1b40
	dc.w $0018,$4e75
.reserves:
	dc.w $102d,$0042,$0200,$000c,$6700,$0012,$1200,$102d
	dc.w $0039,$0c01,$000c,$6700,$0004,$e248,$1600,$e248
	dc.w $d600,$d000,$4241,$1200,$4a6d,$0006,$6600,$0004
	dc.w $d201,$082d,$0000,$000e,$6700,$0006,$0601,$0060
	dc.w $302d,$0004,$9041,$6a00,$0004,$4240,$3b40,$0004
	dc.w $1003,$d000,$1200,$4a6d,$0004,$6600,$0004,$d201
	dc.w $082d,$0001,$000e,$6700,$0006,$0601,$0060,$302d
	dc.w $0006,$9041,$6a00,$0004,$4240,$3b40,$0006

; a0=authoritative player, a1=prepared clone. Call once after each world tick's
; motion/weapons/damage/script sequence. Never call per render or per field.
; Return 0 not periodic, 1 reserves updated, 2 flight-end handling required.
; The owner must perform native flight-end cleanup on 2, or remaining periodic
; RNG/housekeeping on 1. This entry does neither and does not advance the tick.
world_reserves_step:
	movem.l d1-d7/a0-a6,-(sp)
	movea.l a0,a5
	moveq #0,d0
	move.w $0c(a5),d0
	andi.w #15,d0
	bne .not_due
	jsr (a1)
	tst.b $18(a5)
	bne .ended
	lea RS_GUARD_SIZE(a1),a0
	jsr (a0)
	moveq #1,d0
	bra .done
.ended:
	moveq #2,d0
	bra .done
.not_due:
	moveq #0,d0
.done:
	movem.l (sp)+,d1-d7/a0-a6
	rts
