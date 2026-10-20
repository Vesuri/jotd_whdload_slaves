; Remaining native periodic housekeeping after reserve depletion. Not installed.
; Requires timing-world-rng.i. Keep native RNG order and object-table accesses.
WP_NATIVE_SIZE equ $82        ; +0598a..+05a0c (excludes loop back branch)
WP_CODE_SIZE equ WP_NATIVE_SIZE+2
WP_SIZE equ WP_CODE_SIZE+4    ; bound native player pointer after code

; a0=validated 0658 hunk 0, a1=even clone, a2=deadline RNG base, a3=hunk 6.
; Return 0/-1, preserve others. Validate relocated calls/reads before writing.
; Nonoverlapping buffers and cache flush are caller responsibilities.
world_periodic_prepare:
	movem.l d1-d2/a0-a6,-(sp)
	movea.l a3,a6
	lea $598a(a0),a4
	cmpi.l #$323c0080,(a4)
	bne .bad
	cmpi.l #$6200006e,$12(a4)
	bne .bad
	cmpi.w #$1039,$26(a4)
	bne .bad
	lea $157b(a3),a5
	cmpa.l $28(a4),a5
	bne .bad
	cmpi.w #$4a39,$5a(a4)
	bne .bad
	lea $395c(a3),a5
	cmpa.l $5c(a4),a5
	bne .bad
	lea .calls(pc),a3
	moveq #7,d2
.validate:
	move.w (a3)+,d1
	cmpi.w #$4eb9,0(a4,d1.w)
	bne .bad
	movea.l a0,a5
	moveq #0,d0
	move.w (a3)+,d0
	adda.l d0,a5
	cmpa.l 2(a4,d1.w),a5
	bne .bad
	dbf d2,.validate
	movea.l a1,a5
	moveq #WP_NATIVE_SIZE/2-1,d2
.copy:
	move.w (a4)+,(a5)+
	dbf d2,.copy
	move.w #$4e75,(a5)
	lea WR_REGISTER_ENTRY(a2),a5
	move.l a5,6(a1)
	lea $3b88(a6),a5
	move.l a5,WP_CODE_SIZE(a1)
	moveq #0,d0
	bra .done
.bad:
	moveq #-1,d0
.done:
	movem.l (sp)+,d1-d2/a0-a6
	rts
.calls:
	dc.w $04,$7a6a,$18,$7b7e,$30,$7b7e,$40,$7bd0
	dc.w $48,$7fbe,$64,$8036,$6c,$7fbe,$7c,$46de

; a0=authoritative player INCLUDING native trailing object tables, a1=clone.
; Call only after world_reserves_step returned 1, once per periodic tick.
; Requires the native player: callbacks also read its absolute coordinates.
; Return 0/-1, preserve other registers. Native object scratch/table, mission,
; notification and RNG writes are real. No preview, rollback or tick advance.
world_periodic_step:
	movem.l d1-d7/a0-a6,-(sp)
	cmpa.l WP_CODE_SIZE(a1),a0
	bne .bad
	movea.l a0,a5
	jsr (a1)
	moveq #0,d0
	bra .done
.bad:
	moveq #-1,d0
.done:
	movem.l (sp)+,d1-d7/a0-a6
	rts
