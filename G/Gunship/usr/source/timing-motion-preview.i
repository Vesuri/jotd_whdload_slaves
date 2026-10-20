; Native 0658 motion preview support, standalone and not installed.
; Clone +0937c..+0979a with world RNG and contact actions bypassed.
; Native branches and the embedded RPM table retain their relative positions.
; Sin calls still use the original immutable helper/table.
MP_CODE_SIZE equ $41e
MP_RECORD_SIZE equ 86

; a0 = validated 0658 code hunk, a1 = even MP_CODE_SIZE-byte code buffer.
; d0 = 0 success, -1 unexpected patch boundary/call target.
; Preserves d1-d7/a0-a6. Validates before writing the destination.
; Caller MUST flush instruction caches before executing the resulting clone.
; Caller owns version validation, allocation and non-overlapping buffers.
motion_preview_prepare:
	movem.l d1-d2/a2-a4,-(sp)
	movea.l a0,a2
	adda.l #$937c,a2
	cmpi.l #$122d001b,(a2)
	bne .bad
	cmpi.l #$302d000e,$f8(a2)
	bne .bad
	cmpi.l #$02400003,$fc(a2)
	bne .bad
	cmpi.l #$4a026700,$224(a2)
	bne .bad
	cmpi.w #$4e75,$41c(a2)
	bne .bad
	lea .sine_calls(pc),a3
	lea $7a44(a0),a4
	moveq #5,d2
.validate:
	move.w (a3)+,d1
	cmpi.w #$4eb9,0(a2,d1.w)
	bne .bad
	cmpa.l 2(a2,d1.w),a4
	bne .bad
	dbf d2,.validate
	cmpi.w #$4eb9,$104(a2)
	bne .bad
	lea $7a5c(a0),a4
	cmpa.l $106(a2),a4
	bne .bad
	cmpi.w #$4eb9,$26c(a2)
	bne .bad
	movea.l a0,a4
	adda.l #$a150,a4
	cmpa.l $26e(a2),a4
	bne .bad
	movea.l a1,a3
	move.w #MP_CODE_SIZE/2-1,d2
.copy:
	move.w (a2)+,(a3)+
	dbf d2,.copy
	; +09474 -> +09492: exclude the world-owned random heading impulse.
	move.l #$6000001c,$f8(a1)
	; +095a0 -> +09636: exclude contact classification, notifications/resets.
	move.l #$60000094,$224(a1)
	moveq #0,d0
	bra .done
.bad:
	moveq #-1,d0
.done:
	movem.l (sp)+,d1-d2/a2-a4
	rts
.sine_calls:
	dc.w $14e,$180,$1a0,$2c6,$304,$33c

; a0 = authoritative player, a1 = separate MP_RECORD_SIZE-byte result,
; a2 = prepared/cache-flushed clone. All registers preserved; CCR unspecified.
; Only the result record and stack may be written. Result includes derived
; values and a whole native motion increment, NOT a fractional field step.
; Ground/RNG consequences must be evaluated separately at the world boundary.
motion_preview:
	movem.l d0-d7/a0-a6,-(sp)
	movea.l a0,a3
	movea.l a1,a4
	moveq #MP_RECORD_SIZE/2-1,d0
.copy:
	move.w (a3)+,(a4)+
	dbf d0,.copy
	movea.l a1,a5
	jsr (a2)
	movem.l (sp)+,d0-d7/a0-a6
	rts
