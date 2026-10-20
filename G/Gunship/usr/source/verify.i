; Diagnostic instruments for the 0658 executable only. Absent from normal builds.
; CUSTOM2=0 leaves the game untouched; nonzero selects the deterministic seed.
; All debugger addresses are published in GSVFY001, not assumed by the harness.
VERIFY_FRAMES = 8192

verify_dispatch:
	movem.l d0-d7/a0-a6,-(sp)
	move.l _verify_seed(pc),d0
	beq .done
	lea pl_scrnmule_658(pc),a3
	cmpa.l a3,a0
	beq .menu
	lea pl_gamemule_658(pc),a3
	cmpa.l a3,a0
	bne .done
	lea verify_marker(pc),a3
	move.l a1,8(a3)
	lea -4(a1),a0
	lea 8(a3),a4
	moveq #8,d0
.hunks:
	lea 4(a0),a5
	move.l a5,(a4)+
	move.l (a0),d1
	lsl.l #2,d1
	movea.l d1,a0
	dbf d0,.hunks
	movea.l 24(a3),a0 ; hunk 4
	move.l _verify_seed(pc),$3cc(a0)
	clr.l 44(a3)
	clr.l 48(a3)
	clr.l 52(a3)
	clr.l 68(a3)
	lea verify_tick_ready(pc),a0
	move.l a0,56(a3)
	lea verify_frames(pc),a0
	move.l a0,60(a3)
	lea verify_frame_tick(pc),a0
	move.l a0,76(a3)
	; Query the current WHDLoad cache policy with an empty change mask.
	; SetCPU also flushes caches: do this only at load time, where the
	; normal LoadSeg callback already flushes before executing the game.
	moveq #0,d0
	moveq #0,d1
	jsr resload_SetCPU(a2)
	move.l d0,72(a3)
	movea.l 8(a3),a1 ; SetCPU may destroy a0/a1
	lea verify_game_patches(pc),a0
	jsr resload_Patch(a2)
	IFD TIMING_INPUT
	bsr timing_input_install
	ENDC
	bra .done
.menu:
	lea verify_menu_base(pc),a3
	move.l a1,(a3)
	move.l _verify_seed(pc),$24c(a1)
	lea verify_audio_seed(pc),a3
	move.l #$6bdf931a,(a3)
	lea verify_menu_patches(pc),a0
	jsr resload_Patch(a2)
.done:
	movem.l (sp)+,d0-d7/a0-a6
	rts

verify_menu_patches:
	PL_START
	PL_P $250,verify_menu_random
	PL_END

; Original menu LFSR and range reduction, without input-counter entropy.
; VBL sound calls use a separate seed so menu dwell time cannot choose the mission.
; ABI: same d0/d1/d2/a0 scratch registers and stack argument as scrnmule:+0250.
verify_menu_random:
	move.l 4(sp),d1
	movea.l verify_menu_base(pc),a0
	move.l a0,d2
	addi.l #$3132,d2
	cmp.l (sp),d2
	beq .audio
	lea $24c(a0),a0
	bra .next
.audio:
	lea verify_audio_seed(pc),a0
.next:
	move.l (a0),d0
	lsr.l #1,d0
	bcc .store
	eori.l #$b40c0000,d0
.store:
	move.l d0,(a0)
	swap d0
	clr.w d0
	swap d0
	divu.w d1,d0
	eor.w d0,2(a0)
	clr.w d0
	swap d0
	rts

verify_game_patches:
	PL_START
	PL_NOP $7a7c,8 ; remove input-counter entropy from simulation RNG
	PL_NOP $7a8e,8
	PL_PS $563a,verify_tick
	PL_PS $44ca,verify_frame
	PL_END

; At the next loop entry, the preceding tick has completed (including AI/weapon work).
; Break on verify_tick_ready and read hunks without modifying emulated memory.
verify_tick:
	movem.l d0/a0,-(sp)
	lea verify_marker(pc),a0
	addq.l #1,48(a0)
	movea.l 32(a0),a5 ; hunk 6
	lea $3b88(a5),a5 ; replay displaced LEA
	cmpi.w #100,12(a5)
	bne .ready
	move.l _verify_scene(pc),d0
	cmpi.l #1,d0
	bne .ready
	tst.w 30(a5)
	beq .ready
	; Combat fixture: dense existing scenery around cells $3B/$4B.
	; Reposition the existing helicopter (slot 5), retaining its type/AI state.
	; Object arrays store coordinate high and low bytes separately (+7B7E/+7BD0).
	move.w #$b000,(a5)
	move.w #$3e00,2(a5)
	move.b #$b0,$5b(a5)
	clr.b $d5(a5)
	move.b #$40,$db(a5)
	clr.b $155(a5)
	move.w #48,28(a5)
	clr.w 42(a5)
	clr.b 53(a5)
	clr.b 54(a5)
	clr.b 55(a5)
	clr.b 61(a5)
	clr.b 62(a5)
	clr.b 63(a5)
	move.b #37,57(a5)
	move.l #1,68(a0)
.ready:
	movem.l (sp)+,d0/a0
verify_tick_ready:
	rts

; Completed swap timestamp, after MakeScreen/RethinkDisplay and buffer toggle.
; Fixed-size log: stop writing at capacity and count overflow, never overwrite memory.
verify_frame:
	movem.l d0/a0-a1,-(sp)
	lea verify_marker(pc),a0
	move.l 44(a0),d0
	cmpi.l #VERIFY_FRAMES,d0
	bhs verify_frame_overflow
	movea.l d0,a1
	adda.l a1,a1
	adda.l a1,a1
	adda.l a1,a1
	adda.l 60(a0),a1 ; offset * 8, without changing the caller's X flag
	movea.l 16(a0),a0 ; hunk 2
	move.l $1c(a0),(a1)+
	movea.l verify_marker+32(pc),a0 ; hunk 6
	move.w $3b94(a0),d0
	move.w d0,(a1)+
	move.w $4bb0(a0),(a1)
	swap d0
	move.w (a1),d0
	swap d0
verify_frame_tick:
	; D0 = back-buffer index : tick, both observed by the CPU.
	; The displayed buffer is back-buffer XOR 1. This avoids stale
	; copyback reads of both the tick and Intuition's changing BitMap.
	lea verify_marker(pc),a0
	movea.l 44(a0),a1
	addq.l #1,a1
	move.l a1,44(a0)
	bra verify_frame_restore
verify_frame_overflow:
	movea.l 52(a0),a1
	addq.l #1,a1
	move.l a1,52(a0)
verify_frame_restore:
	movea.l verify_marker+8(pc),a0
	adda.l #$c757,a0
	clr.b (a0) ; replay displaced instruction
	movem.l (sp)+,d0/a0-a1
	rts

verify_menu_base: dc.l 0
verify_audio_seed: dc.l 0
verify_marker:
	dc.b "GSVFY001"
	ds.l 9 ; +8: game hunk bases 0..8
	dc.l 0 ; +44: frame count
	dc.l 0 ; +48: tick-entry count (first entry has no completed predecessor)
	dc.l 0 ; +52: dropped frames
	dc.l 0 ; +56: tick checkpoint PC
	dc.l 0 ; +60: frame log address
	dc.l VERIFY_FRAMES ; +64: capacity
	dc.l 0 ; +68: combat fixture applied
	dc.l 0 ; +72: WHDLoad cache policy at game load (SetCPU with mask=0)
	dc.l 0 ; +76: completed-swap checkpoint, CPU tick in d0.w
verify_frames:
	ds.b VERIFY_FRAMES*8
