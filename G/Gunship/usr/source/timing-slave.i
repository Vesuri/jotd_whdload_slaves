; Experimental TIMING_RUNTIME setup/input capture; no flight consumer hook.
; CUSTOM1 gates allocation/preparation. Production activation remains pending.
; LoadSeg's existing post-callback cache flush covers the prepared copies.
timing_runtime_dispatch:
 movem.l d0-d7/a0-a6,-(sp)
 move.l _custom1(pc),d0
 beq .done
 lea pl_gamemule_658(pc),a3
 cmpa.l a3,a0
 bne .done
 movea.l a1,a0
 lea timing_runtime_hunk_table(pc),a1
 bsr timing_runtime_hunks
 tst.l d0
 bne .status
 movea.l 4.w,a6
 moveq #0,d7
 move.b VBlankFrequency(a6),d7
 cmpi.w #50,d7
 beq .rate
 cmpi.w #60,d7
 bne .rate_bad
.rate:
 move.l timing_runtime_arena(pc),d0
 bne .allocated
 move.l #RT_ARENA_SIZE,d0
 move.l #MEMF_PUBLIC|MEMF_CLEAR,d1
 jsr _LVOAllocMem(a6)
 tst.l d0
 beq .memory_bad
 lea timing_runtime_arena(pc),a0
 move.l d0,(a0)
.allocated:
 movea.l d0,a0
 ; Reuse only an inactive arena at a later game-module load.
 tst.w RT_CLOCK+TC_ACTIVE(a0)
 bne .active
 tst.w RT_HISTORY+TH_ACTIVE(a0)
 bne .active
 tst.w RT_COMMANDS+CQ_ACTIVE(a0)
 bne .active
 tst.w RT_SCHEDULER+TS_STATE(a0)
 bne .active
 lea timing_runtime_hunk_table(pc),a1
 move.l d7,d0
 bsr timing_runtime_prepare
 tst.l d0
 bne .status
 movea.l timing_runtime_arena(pc),a0
 bsr timing_live_install
 tst.l d0
 bne .status
 movea.l timing_runtime_arena(pc),a0
 bsr timing_vbl_install
 tst.l d0
 bne .status
 movea.l timing_runtime_arena(pc),a0
 bsr timing_render_install
 tst.l d0
 bne .status
 movea.l timing_runtime_arena(pc),a0
 bsr timing_map_install
 tst.l d0
 bne .status
 movea.l timing_runtime_arena(pc),a0
 bsr timing_gauges_install
 tst.l d0
 bne .status
 movea.l timing_runtime_arena(pc),a0
 bsr timing_target_view_install
 tst.l d0
 bne .status
 movea.l timing_runtime_arena(pc),a0
 bsr timing_actor_generation_install
 tst.l d0
 bne .status
 movea.l timing_runtime_arena(pc),a0
 bsr timing_script_generation_install
 tst.l d0
 bne .status
 movea.l timing_runtime_arena(pc),a0
 bsr timing_script_heading_install
.status:
 lea timing_runtime_status(pc),a0
 move.l d0,(a0)
.done:
 movem.l (sp)+,d0-d7/a0-a6
 rts
.memory_bad:
 moveq #-2,d0
 bra .status
.rate_bad:
 moveq #-3,d0
 bra .status
.active:
 moveq #-4,d0
 bra .status

; Called after the main program returns. Native input callbacks must have
; stopped before their shared arena can be released.
timing_runtime_release:
 movem.l d0-d1/a0-a1/a6,-(sp)
 lea timing_runtime_arena(pc),a0
 move.l (a0),d0
 beq .done
 clr.l (a0)
 movea.l d0,a1
 move.l #RT_ARENA_SIZE,d0
 movea.l 4.w,a6
 jsr _LVOFreeMem(a6)
.done:
 movem.l (sp)+,d0-d1/a0-a1/a6
 rts
 even
timing_runtime_arena: dc.l 0
timing_runtime_status: dc.l 0 ; 0 prepared, -1 signatures/chain, -2 memory,
                              ; -3 unsupported frequency, -4 active/pending arena
timing_runtime_hunk_table: ds.l 9
