; Enhanced supervisor stack in optional WHDLoad-managed expansion memory.
; The slave hunk itself is not a valid stack on WHDLoad interrupt entry.
; Original $a876c discards the trap frame and establishes a new stack;
; do not transplant an active frame. Keep IRQs disabled during the switch.
STEP_STACK_SIZE = $4000
step_stack_start:
	move.w #$2700,sr
	movem.l d0/a0-a1,-(a7)
	lea step_stack_start(pc),a0
	adda.l #_expmem-step_stack_start,a0
	move.l (a0),a0
	cmpa.l #$200000,a0
	bcs .original
	cmpa.l #$a00000,a0
	bcs .fast
	cmpa.l #$1000000,a0
	bcs .original
.fast:
	IFD VERIFY_C_GEOMETRY_LUT
	move.l d1,-(a7)
	bsr step_geometry_init
	move.l (a7)+,d1
	ENDC
	move.l a0,a1
	move.w #(STEP_STACK_SIZE+32)/4-1,d0
.fill:
	move.l #$a55aa55a,(a0)+
	dbf d0,.fill
	lea step_stack_stats(pc),a0
	addq.l #1,12(a0)
	lea 16(a1),a1
	move.l a1,16(a0)
	lea STEP_STACK_SIZE(a1),a1
	move.l a1,20(a0)
	movem.l (a7)+,d0/a0-a1
	move.l step_stack_stats+20(pc),a7
	move.w #$2700,sr
	jmp $a8776
.original:
	movem.l (a7)+,d0/a0-a1
	lea $77cbe,a7
	move.w #$2700,sr
	jmp $a8776

	cnop 0,4
step_stack_stats:
	dc.b "RRCSTK01"
	dc.l STEP_STACK_SIZE,0,0,0 ; size, initialization count, bottom, top

	IFD VERIFY_C_GEOMETRY_LUT
; d6 is 256-fraction + 256*row: 1..8192 inclusive for the 32 rows.
; Install one 020 full-extension indexed lookup only after Fast allocation.
; MOVE.W (table.l,ZA0,D6.W*2),$64(A3); NOP is 12 bytes, like the original
; MOVE.L #$1c00,D2; DIVU.W D6,D2; MOVE.W D2,$64(A3).
; The following native instruction clears d2; its result is not otherwise used.
step_geometry_init:
	lea $5000(a0),a1
	lea step_geometry_table(pc),a0
	move.l a1,(a0)
	clr.w (a1)+ ; unused zero divisor
	moveq #1,d0
.next:
	move.l #$1c00,d1
	divu.w d0,d1
	move.w d1,(a1)+
	addq.w #1,d0
	cmpi.w #8192,d0
	bls .next
	move.l #$377063b0,$8984e
	move.l step_geometry_table(pc),$89852
	move.l #$00644e71,$89856
	lea step_stack_start(pc),a1
	adda.l #_resload-step_stack_start,a1
	move.l (a1),a1
	jsr (resload_FlushCache,a1)
	move.l step_geometry_table(pc),a0
	suba.l #$5000,a0
	rts
	cnop 0,4
step_geometry_table:
	dc.l 0
	ENDC
