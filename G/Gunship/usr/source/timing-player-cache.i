; Optional exact-input cache for player_step_interval. Runtime-owned when enabled.
; Requires player-step. Foreground/serialized use, disjoint buffers only.
; The prepared native stages and sine helper must remain immutable while
; valid. Clear PC_VALID on lifecycle/reset or before changing either code
; buffer, even if its address stays the same. No approximate/masked keys.
PC_VALID equ 0
PC_KEY equ 2
PC_KEY_SIZE equ MP_RECORD_SIZE+PS_SIZE+PS_INPUT_SIZE+12
PC_STATE equ PC_KEY+PC_KEY_SIZE
PC_PLAYER equ PC_STATE+PS_SIZE
PC_SIZE equ PC_PLAYER+MP_RECORD_SIZE

; Original interval ABI plus a5=PC_SIZE cache, initially zero, or null to
; bypass. Key covers the entire player, initialized step state, input packet,
; logical tick and both code pointers. Hit restores both outputs. Miss calls
; the original routine; failure leaves the old cache and caller data intact.
; Return d0=0/-1, all other registers preserved. CCR is not an output.
player_step_cached_interval:
	cmpa.w #0,a5
	beq player_step_interval
	movem.l d0-d7/a0-a6,-(sp)
	lea -PC_KEY_SIZE(sp),sp
	movea.l a5,a6
	; Compare in place on the common hit path. Build a preserved key only
	; for a miss, before the native routine changes the input buffers.
	; Fixed-size comparisons avoid per-longword loop overhead. Keep an
	; early miss after EVERY comparison, including the exact word tail.
	cmpi.w #1,PC_VALID(a6)
	bne .prepare_miss
	cmp.l PC_KEY+MP_RECORD_SIZE+PS_SIZE+PS_INPUT_SIZE(a6),d0
	bne .prepare_miss
	cmpa.l PC_KEY+MP_RECORD_SIZE+PS_SIZE+PS_INPUT_SIZE+4(a6),a2
	bne .prepare_miss
	cmpa.l PC_KEY+MP_RECORD_SIZE+PS_SIZE+PS_INPUT_SIZE+8(a6),a3
	bne .prepare_miss
	lea PC_KEY(a6),a5
	REPT MP_RECORD_SIZE/4
	cmpm.l (a1)+,(a5)+
	bne .prepare_miss
	ENDR
	IFNE MP_RECORD_SIZE&2
	cmpm.w (a1)+,(a5)+
	bne .prepare_miss
	ENDC
	REPT PS_SIZE/4
	cmpm.l (a0)+,(a5)+
	bne .prepare_miss
	ENDR
	IFNE PS_SIZE&2
	cmpm.w (a0)+,(a5)+
	bne .prepare_miss
	ENDC
	REPT PS_INPUT_SIZE/4
	cmpm.l (a4)+,(a5)+
	bne .prepare_miss
	ENDR
	IFNE PS_INPUT_SIZE&2
	cmpm.w (a4)+,(a5)+
	bne .prepare_miss
	ENDC
	; Reload caller destinations from the saved register frame.
	movea.l PC_KEY_SIZE+32(sp),a0
	movea.l PC_KEY_SIZE+36(sp),a1
	lea PC_STATE(a6),a2
	moveq #PS_SIZE/16-1,d1
.hit_state:
	REPT 4
	move.l (a2)+,(a0)+
	ENDR
	dbf d1,.hit_state
	REPT PS_SIZE/4-(PS_SIZE/16)*4
	move.l (a2)+,(a0)+
	ENDR
	IFNE PS_SIZE&2
	move.w (a2)+,(a0)+
	ENDC
	moveq #MP_RECORD_SIZE/16-1,d1
.hit_player:
	REPT 4
	move.l (a2)+,(a1)+
	ENDR
	dbf d1,.hit_player
	REPT MP_RECORD_SIZE/4-(MP_RECORD_SIZE/16)*4
	move.l (a2)+,(a1)+
	ENDR
	IFNE MP_RECORD_SIZE&2
	move.w (a2)+,(a1)+
	ENDC
	moveq #0,d0
	bra .done
.prepare_miss:
	movem.l PC_KEY_SIZE(sp),d0-d7/a0-a6
	movea.l sp,a5
	moveq #MP_RECORD_SIZE/4-1,d1
.key_player:
	move.l (a1)+,(a5)+
	dbf d1,.key_player
	IFNE MP_RECORD_SIZE&2
	move.w (a1)+,(a5)+
	ENDC
	moveq #PS_SIZE/4-1,d1
.key_state:
	move.l (a0)+,(a5)+
	dbf d1,.key_state
	IFNE PS_SIZE&2
	move.w (a0)+,(a5)+
	ENDC
	REPT PS_INPUT_SIZE/4
	move.l (a4)+,(a5)+
	ENDR
	IFNE PS_INPUT_SIZE&2
	move.w (a4)+,(a5)+
	ENDC
	move.l d0,(a5)+
	move.l a2,(a5)+
	move.l a3,(a5)+
.miss:
	movem.l PC_KEY_SIZE(sp),d0-d7/a0-a6
	bsr player_step_interval
	tst.l d0
	bne .done
	movea.l a5,a6
	movea.l sp,a2
	lea PC_KEY(a6),a3
	moveq #PC_KEY_SIZE/4-1,d1
.save_key:
	move.l (a2)+,(a3)+
	dbf d1,.save_key
	moveq #PS_SIZE/16-1,d1
.save_state:
	REPT 4
	move.l (a0)+,(a3)+
	ENDR
	dbf d1,.save_state
	REPT PS_SIZE/4-(PS_SIZE/16)*4
	move.l (a0)+,(a3)+
	ENDR
	IFNE PS_SIZE&2
	move.w (a0)+,(a3)+
	ENDC
	moveq #MP_RECORD_SIZE/16-1,d1
.save_player:
	REPT 4
	move.l (a1)+,(a3)+
	ENDR
	dbf d1,.save_player
	REPT MP_RECORD_SIZE/4-(MP_RECORD_SIZE/16)*4
	move.l (a1)+,(a3)+
	ENDR
	IFNE MP_RECORD_SIZE&2
	move.w (a1)+,(a3)+
	ENDC
	move.w #1,PC_VALID(a6)
.done:
	lea PC_KEY_SIZE+4(sp),sp
	movem.l (sp)+,d1-d7/a0-a6
	rts
