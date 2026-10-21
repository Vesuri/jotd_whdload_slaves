; Distribute the ten continuous fields of a native player preview.
; Requires timing-endpoint-fraction.i. Standalone, not installed.
EM_COUNT equ 10
EM_SIZE equ EM_COUNT*4

; Emit executable fixed-type field operations and the public layout table
; from the same list. Types/offsets are immutable; no per-field dispatch.
EM_ITEM MACRO
 IFNE EM_EMIT_CODE
 moveq #0,d0
 moveq #0,d1
 IFNE (\2)&1
 move.w \1(a2),d0
 move.w \1(a1),d1
 ELSE
 move.b \1(a2),d0
 move.b \1(a1),d1
 ENDC
 IFNE (\2)&2
 IFEQ (\2)&1
 ext.w d0
 ext.w d1
 ENDC
 ext.l d0
 ext.l d1
 ENDC
 sub.l d1,d0
 IFNE (\2)&4
 IFEQ (\2)&1
 ext.w d0
 ENDC
 ext.l d0
 ENDC
 tst.l d2
 beq .scaled\@
 tst.l d0
 beq .scaled\@
 move.l d0,d3
 bpl .positive\@
 neg.l d0
.positive\@:
 mulu.w d2,d0
 tst.l d3
 bpl .add\@
 neg.l d0
.add\@:
 add.l (a0),d0
 divs.w #EF_DEN,d0
 move.l d0,d1
 ext.l d0
 swap d1
 ext.l d1
 bpl .remainder\@
 subq.l #1,d0
 addi.l #EF_DEN,d1
.remainder\@:
 move.l d1,(a0)
.scaled\@:
 IFNE (\2)&1
 add.w d0,\1(a3)
 ELSE
 add.b d0,\1(a3)
 ENDC
 addq.l #4,a0
 ELSE
 dc.w \1,\2
 ENDC
 ENDM

EM_FIELDS MACRO
 EM_ITEM 0,5 ; X, modulo 65536
 EM_ITEM 2,5 ; Y, modulo 65536
 EM_ITEM 28,1 ; height, unsigned
 EM_ITEM 42,3 ; forward speed, signed
 EM_ITEM 27,0 ; RPM, unsigned
 EM_ITEM 53,4 ; heading, modulo 256
 EM_ITEM 61,4 ; track, modulo 256
 EM_ITEM 54,2 ; pitch, signed
 EM_ITEM 55,2 ; roll, signed
 EM_ITEM 62,2 ; vertical speed, signed
 ENDM

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
	moveq #0,d2 ; whole tick: no fractional scaling
	cmpi.l #1,d0
	beq .validate
	moveq #85,d2
	cmpi.l #16,d0
	beq .validate
	moveq #80,d2
	cmpi.l #17,d0
	beq .validate
	moveq #68,d2
	cmpi.l #20,d0
	bne .bad
.validate:
	movea.l a0,a4
	moveq #EM_COUNT-1,d7
.residue:
	cmpi.l #EF_DEN,(a4)+
	bhs .bad
	dbf d7,.residue
 ; Span and every residue are valid before any generated operation writes.
 ; Each immutable field type bounds its delta to [-65535,65535].
EM_EMIT_CODE SET 1
 EM_FIELDS
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
EM_EMIT_CODE SET 0
 EM_FIELDS
