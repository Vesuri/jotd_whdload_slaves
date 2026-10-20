; Distribute the ten continuous fields of a native player preview.
; Requires timing-endpoint-fraction.i. Standalone, not installed.
EM_COUNT equ 10
EM_SIZE equ EM_COUNT*4

; a0=EM_SIZE bytes of fractional residues, initially zero,
; a1=86-byte interval anchor, a2=86-byte fresh native candidate,
; a3=current 86-byte player record, d0=interval length 1/16/17/20.
; Returns d0=0/-1; other registers preserved. Invalid input writes nothing.
; Only continuous player fields and their residues are written. All other
; bytes, including clock, commands and world state, remain untouched.
; Serialized caller owns distinct aligned buffers, anchor lifetime, preview
; construction, derived outputs, publication, ground handling and rebasing.
; Residues stay in [0,1360); retain them across interval-length changes.
endpoint_motion_step:
	movem.l d1-d7/a0-a4,-(sp)
	move.l d0,d6
	cmpi.l #1,d0
	beq .validate
	cmpi.l #16,d0
	beq .validate
	cmpi.l #17,d0
	beq .validate
	cmpi.l #20,d0
	bne .bad
.validate:
	movea.l a0,a4
	moveq #EM_COUNT-1,d7
.residue:
	cmpi.l #EF_DEN,(a4)+
	bhs .bad
	dbf d7,.residue
	lea endpoint_motion_fields(pc),a4
	moveq #EM_COUNT-1,d7
.field:
	move.w (a4)+,d5
	move.w (a4)+,d4
	moveq #0,d0
	moveq #0,d1
	btst #0,d4
	beq .bytes
	move.w (a2,d5.w),d0
	move.w (a1,d5.w),d1
	btst #1,d4
	beq .delta
	ext.l d0
	ext.l d1
	bra .delta
.bytes:
	move.b (a2,d5.w),d0
	move.b (a1,d5.w),d1
	btst #1,d4
	beq .delta
	ext.w d0
	ext.l d0
	ext.w d1
	ext.l d1
.delta:
	sub.l d1,d0
	btst #2,d4
	beq .scale
	btst #0,d4
	bne .circular_word
	ext.w d0
.circular_word:
	ext.l d0
.scale:
	move.l d6,d1
	bsr endpoint_fraction_step
	; All arguments were validated before any writes. The field types
	; bound every delta to [-65535,65535], so this cannot fail.
	btst #0,d4
	beq .store_byte
	add.w d0,(a3,d5.w)
	bra .next
.store_byte:
	add.b d0,(a3,d5.w)
.next:
	addq.l #4,a0
	dbf d7,.field
	moveq #0,d0
	bra .done
.bad:
	moveq #-1,d0
.done:
	movem.l (sp)+,d1-d7/a0-a4
	rts

; Flags: bit0 word (else byte), bit1 signed, bit2 circular shortest delta.
; Residue order is part of the presentation/shadow-state interface.
endpoint_motion_fields:
	dc.w 0,5	; X, modulo 65536
	dc.w 2,5	; Y, modulo 65536
	dc.w 28,1	; height, unsigned
	dc.w 42,3	; forward speed, signed
	dc.w 27,0	; RPM, unsigned
	dc.w 53,4	; heading, modulo 256
	dc.w 61,4	; track, modulo 256
	dc.w 54,2	; pitch, signed
	dc.w 55,2	; roll, signed
	dc.w 62,2	; vertical speed, signed
