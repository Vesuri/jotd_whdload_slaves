; Native-quantized displacement scaled per field. Not installed.
; Requires timing-fraction.i. World contact consequences remain separate.
MV_RATE equ 0
MV_CONTACT equ 2          ; latched nonzero-height -> zero crossing
MV_HEIGHT equ 4           ; normalized nonnegative remainder after height step
MV_X equ 8
MV_Y equ 12
MV_WAS_AIRBORNE equ 16    ; previous height-step input was nonzero (0/1)
MV_SIZE equ 20            ; final word reserved

; a0=state, d0=50/60 or h=1 fixture 3. Return d0=0/-1.
movement_init:
	cmpi.l #50,d0
	beq .valid
	cmpi.l #60,d0
	beq .valid
	cmpi.l #3,d0
	bne .bad
.valid:
	clr.l (a0)
	move.w d0,MV_RATE(a0)
	clr.l MV_HEIGHT(a0)
	clr.l MV_X(a0)
	clr.l MV_Y(a0)
	clr.l MV_WAS_AIRBORNE(a0)
	moveq #0,d0
	rts
.bad:
	moveq #-1,d0
	rts

; a0=state, a1=private player. REPLACES native height stage 2.
; Return d0=0/-1; preserves other registers. No landing/damage notifications.
movement_height:
	movem.l d1-d7/a0-a6,-(sp)
	movea.l a0,a4
	movea.l a1,a5
	bsr movement_check
	tst.l d0
	bne .bad
	moveq #0,d6
	tst.w $1c(a5)
	beq .previous
	moveq #1,d6
.previous:
	move.w $0c(a5),d0
	andi.w #1,d0
	addq.b #1,d0
	add.b $3e(a5),d0
	asr.b #2,d0
	ext.w d0
	ext.l d0
	lea MV_HEIGHT(a4),a0
	moveq #3,d1
	bsr fraction_scale
	add.w $1c(a5),d0
	bmi .floor
	bne .height
	tst.l MV_HEIGHT(a4)
	bpl .height
.floor:
	clr.w d0
	clr.l MV_HEIGHT(a4)
.height:
	; Altitude is nonnegative: publish its floor as the native integer.
	; A negative fraction otherwise hides a crossed integer/high-byte
	; boundary from native lift/ground predicates until a whole unit accrues.
	; Preserve the exact total; .floor already handles negative total height.
	tst.l MV_HEIGHT(a4)
	bpl .store_height
	subq.w #1,d0
	add.l d2,MV_HEIGHT(a4)
.store_height:
	move.w d0,$1c(a5)
	move.w d6,MV_WAS_AIRBORNE(a4)
	tst.w d0
	bne .ok
	tst.w d6
	beq .ok
	move.w #1,MV_CONTACT(a4)
.ok:
	moveq #0,d0
	bra .done
.bad:
	moveq #-1,d0
.done:
	movem.l (sp)+,d1-d7/a0-a6
	rts

; a0=state, a1=private player, a2=validated native sine helper (+07a44).
; REPLACES native coarse-speed/coordinate/wind stage 5.
; Return d0=0/-1; preserves other registers. Bounds precede wind as native.
movement_horizontal:
	movem.l d1-d7/a0-a6,-(sp)
	movea.l a0,a4
	movea.l a1,a5
	movea.l a2,a6
	bsr movement_check
	tst.l d0
	bne .bad
	move.w $2a(a5),d0
	asr.w #2,d0
	move.b d0,$50(a5)
	move.b d0,d1
	ext.w d1
	move.b $3d(a5),d0
	jsr (a6)
	ext.l d0
	lea MV_X(a4),a0
	moveq #3,d1
	bsr fraction_scale
	lea 0(a5),a3
	bsr .coordinate
	move.b $50(a5),d1
	ext.w d1
	move.b $3d(a5),d0
	addi.b #64,d0
	jsr (a6)
	ext.l d0
	lea MV_Y(a4),a0
	moveq #3,d1
	bsr fraction_scale
	lea 2(a5),a3
	bsr .coordinate
	tst.w $1c(a5)
	beq .ok
	move.b $14(a5),d0
	ext.w d0
	ext.l d0
	lea MV_X(a4),a0
	moveq #3,d1
	bsr fraction_scale
	add.w d0,0(a5)
	move.b $15(a5),d0
	ext.w d0
	ext.l d0
	lea MV_Y(a4),a0
	moveq #3,d1
	bsr fraction_scale
	add.w d0,2(a5)
.ok:
	moveq #0,d0
	bra .done
.bad:
	moveq #-1,d0
.done:
	movem.l (sp)+,d1-d7/a0-a6
	rts
.coordinate:
	; a0=fraction, a3=coordinate. Native unsigned bounds after word addition.
	add.w (a3),d0
	cmpi.w #$1800,d0
	blo .low
	cmpi.w #$d800,d0
	bhi .high
	beq .upper_edge
	cmpi.w #$1800,d0
	bne .store
	tst.l (a0)
	bmi .discard
	bra .store
.upper_edge:
	tst.l (a0)
	bgt .discard
	bra .store
.low:
	move.w #$1800,d0
	bra .discard
.high:
	move.w #$d800,d0
.discard:
	clr.l (a0)
.store:
	move.w d0,(a3)
	rts

; World consumer acknowledges only after evaluating the pending contact.
; Does not clear latest pre-step airborne information or movement fractions.
movement_ack_contact:
	clr.w MV_CONTACT(a0)
	rts

; Internal: a4=state; d0=0/-1, d2=rate; clobbers d1/d3/a3.
movement_check:
	moveq #0,d2
	move.w MV_RATE(a4),d2
	cmpi.w #50,d2
	beq .rate_ok
	cmpi.w #60,d2
	beq .rate_ok
	cmpi.w #3,d2
	bne .bad
.rate_ok:
	cmpi.w #1,MV_CONTACT(a4)
	bhi .bad
	cmpi.w #1,MV_WAS_AIRBORNE(a4)
	bhi .bad
	lea MV_HEIGHT(a4),a3
	moveq #2,d1
.fraction:
	move.l (a3)+,d3
	cmp.l d2,d3
	bge .bad
	move.l d2,d0
	neg.l d0
	cmp.l d0,d3
	ble .bad
	cmpi.w #3,d2
	bne .next
	tst.l d3
	bne .bad
.next:
	dbf d1,.fraction
	moveq #0,d0
	rts
.bad:
	moveq #-1,d0
	rts
