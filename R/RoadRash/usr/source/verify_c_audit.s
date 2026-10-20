; Diagnostic boundary snapshots for the simulation/presentation ownership audit.
; Copies change execution time: use only functional runs, never FPS measurements.
; One selected frame is frozen at three boundaries. Includes IRQ-written state;
; a changed byte is evidence of a dependency, not proof of its writer.
	IFND VERIFY_C_AUDIT_FRAME
VERIFY_C_AUDIT_FRAME = 40
	ENDC
VERIFY_C_AUDIT_START = $a5900
VERIFY_C_AUDIT_SIZE = $a8740-VERIFY_C_AUDIT_START

verify_c_sim_begin:
	move.w	sr,-(a7)
	movem.l	d0-d1/a0-a1,-(a7)
	lea	verify_c_audit(pc),a0
	addq.l	#1,8(a0)
	moveq	#0,d0
	bsr	verify_c_capture
	movem.l	(a7)+,d0-d1/a0-a1
	move.w	(a7)+,ccr
	cmpi.w	#$20,$a59da        ; displaced comparison
	rts

verify_c_render_begin:
	move.w	sr,-(a7)
	movem.l	d0-d1/a0-a1,-(a7)
	lea	verify_c_audit(pc),a0
	moveq	#1,d0
	bsr	verify_c_capture
	movem.l	(a7)+,d0-d1/a0-a1
	move.w	(a7)+,ccr
	jmp	$89138               ; displaced camera update

verify_c_render_end:
	move.w	sr,-(a7)
	movem.l	d0-d1/a0-a1,-(a7)
	lea	verify_c_audit(pc),a0
	moveq	#2,d0
	bsr	verify_c_capture
	movem.l	(a7)+,d0-d1/a0-a1
	move.w	(a7)+,ccr
	jmp	$871dc               ; displaced BSR plus RTS, including VERIFY hook

verify_c_capture:
	cmpi.l	#VERIFY_C_AUDIT_FRAME,8(a0)
	bne.b	.done
	move.l	d0,d1
	lsl.w	#2,d1
	move.l	$a5d4c,24(a0,d1.w)
	bset	d0,15(a0)            ; completed-boundary mask (low byte)
	mulu.w	#VERIFY_C_AUDIT_SIZE,d0
	lea	verify_c_snapshots(pc),a1
	adda.l	d0,a1
	lea	VERIFY_C_AUDIT_START,a0
	move.w	#VERIFY_C_AUDIT_SIZE/4-1,d1
.copy:
	move.l	(a0)+,(a1)+
	dbf	d1,.copy
.done:
	rts

	cnop	0,4
verify_c_audit:
	dc.b	'RRCAUD01'
	dc.l	0,0                  ; +8 main-loop calls, +12 captured mask
	dc.l	VERIFY_C_AUDIT_START,VERIFY_C_AUDIT_SIZE
	dc.l	0,0,0                ; +24 race field at each boundary
	dc.l	VERIFY_C_AUDIT_FRAME  ; +36 selected frame
verify_c_snapshots:
	ds.b	VERIFY_C_AUDIT_SIZE*3
