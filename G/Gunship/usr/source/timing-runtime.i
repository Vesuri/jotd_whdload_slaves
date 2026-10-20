; One caller-allocated, even runtime arena for the validated 0658 executable.
; Requires timing-core.i. Not installed. Native hunks and arena must not overlap.
; Preparation does not patch or execute game code. Flush instruction caches
; after success and before any copied native entry executes.
RT_READY equ 0
RT_HUNKS equ 4 ; nine native hunk pointers, already validated by loader
RT_CLOCK equ RT_HUNKS+36
RT_HISTORY equ RT_CLOCK+TC_STATE_SIZE
RT_COMMANDS equ RT_HISTORY+TH_SIZE
RT_SCHEDULER equ RT_COMMANDS+CQ_SIZE
RT_RECORD equ RT_SCHEDULER+TS_SIZE
RT_ENDPOINT equ RT_RECORD+TH_RECORD_SIZE
RT_PACKET equ RT_ENDPOINT+EP_SIZE
RT_MODE equ RT_PACKET+PS_INPUT_SIZE
RT_PLAYER_READER equ RT_MODE+CM_SIZE
RT_WORLD_READER equ RT_PLAYER_READER+CP_SIZE
RT_FIELD equ RT_WORLD_READER+CW_SIZE
RT_START equ RT_FIELD+SF_SIZE
RT_IMPULSES equ RT_START+SW_SIZE
RT_PLAYER equ RT_IMPULSES+SI_SIZE
RT_GEOMETRY equ RT_PLAYER+SE_GROUND_SIZE
RT_BODY equ RT_GEOMETRY+SGE_SIZE
RT_CONSUMER equ RT_BODY+WB_SIZE
RT_MODAL equ RT_CONSUMER+TF_SIZE
RT_EVENT equ RT_MODAL+TM_SIZE
RT_FIRE equ RT_EVENT+GD_SIZE
RT_HEADING equ RT_FIRE+2
RT_PENDING equ RT_HEADING+2
RT_CAMERA equ RT_PENDING+2
RT_CAPTURE equ RT_CAMERA+12
RT_NATIVE_DISCARDED equ RT_CAPTURE ; lifetime native FIFO entries discarded
RT_CAPTURE_OWNER equ RT_CAPTURE+38 ; 0 native FIFO, 1 runtime owns accepted keys
RT_SAMPLE equ RT_CAPTURE+48
RT_STAGES equ RT_SAMPLE+TH_RECORD_SIZE
RT_DECODER equ RT_STAGES+MS_CODE_SIZE
RT_RNG equ RT_DECODER+WC_CODE_SIZE
RT_HIT equ RT_RNG+WR_CODE_SIZE
RT_EFFECTS equ RT_HIT+WH_CODE_SIZE
RT_WEAPONS equ RT_EFFECTS+WE_CODE_SIZE
RT_DAMAGE equ RT_WEAPONS+WW_SIZE
RT_SCRIPT equ RT_DAMAGE+WD_SIZE
RT_RESERVES equ RT_SCRIPT+SC_SIZE
RT_PERIODIC equ RT_RESERVES+RS_CODE_SIZE
RT_CLEANUP equ RT_PERIODIC+WP_SIZE
RT_OPENING equ RT_CLEANUP+WT_CLEANUP_SIZE
RT_GUIDANCE equ RT_OPENING+WS_CODE_SIZE
RT_GROUND equ RT_GUIDANCE+FG_SIZE
RT_SCENE equ RT_GROUND+GR_CODE_SIZE
RT_GUIDANCE_PRESENT equ RT_SCENE+SCENE_SIZE
RT_BATCH equ RT_GUIDANCE_PRESENT+GP_SIZE ; 0 idle, 1 running, 2 command,
                                        ; 3 modal, 4 end, 5 fault, 6 excess
RT_BOUNDARY equ RT_BATCH+2
RT_BOUNDARY_RECORD equ RT_BOUNDARY+BC_SIZE
RT_BOUNDARY_PHASE equ RT_BOUNDARY_RECORD+8 ; 0 ready, 1 suspended, 2 executing,
                                         ; 3 applied/unmarked, 4 marked,
                                         ; 5 marked/end, 6 failed
RT_BOUNDARY_RESULT equ RT_BOUNDARY_PHASE+2
RT_BOUNDARY_ABORTS equ RT_BOUNDARY_RESULT+2 ; lifetime delivered fields exited
RT_PRESENT_INSTRUMENTS equ RT_BOUNDARY_ABORTS+4
RT_PRESENT_SCENE equ RT_PRESENT_INSTRUMENTS+16
RT_VISIBILITY equ RT_PRESENT_SCENE+SCENE_STATE_SIZE
RT_TARGET equ RT_VISIBILITY+VR_SIZE
RT_TARGET_PHASE equ RT_TARGET+WT_SIZE ; 0 fresh, 1 collecting, 2 published, 3 fault
RT_TARGET_FIELD equ RT_TARGET_PHASE+2
RT_GAUGES equ RT_TARGET_FIELD+4
RT_GAUGE_PHASE equ RT_GAUGES+GA_SIZE ; 0 fresh, 1 applying, 2 complete
RT_GAUGE_FIELD equ RT_GAUGE_PHASE+2
RT_GAUGE_SCRATCH equ RT_GAUGE_FIELD+4 ; 16-byte instruments + 12-byte camera
RT_VIEW equ RT_GAUGE_SCRATCH+28
RT_VIEW_SAVED equ RT_VIEW+TPV_SIZE
RT_VIEW_PHASE equ RT_VIEW_SAVED+WT_STATE_SIZE ; 0 closed, 1 collecting, 2 drawing
RT_ACTOR_GENERATIONS equ RT_VIEW_PHASE+2
RT_ACTOR_PREVIEW equ RT_ACTOR_GENERATIONS+AG_SIZE
RT_ACTOR_PRESENT equ RT_ACTOR_PREVIEW+AP_SIZE
RT_ACTOR_COORDS equ RT_ACTOR_PRESENT+AC_SIZE
RT_RELEASE_PRESENT equ RT_ACTOR_COORDS+36
RT_RELEASE_COORDS equ RT_RELEASE_PRESENT+AC_SIZE
RT_SCRIPT_GENERATION equ RT_RELEASE_COORDS+36
RT_SCRIPT_PRESENT equ RT_SCRIPT_GENERATION+AG_SIZE
RT_SCRIPT_POSE equ RT_SCRIPT_PRESENT+SPC_SIZE
RT_SCRIPT_BITMAP equ RT_SCRIPT_POSE+8
RT_DRAW_ENTRY equ RT_SCRIPT_BITMAP+4
RT_DRAW_READY equ RT_DRAW_ENTRY+4
RT_SCRIPT_PREVIEW equ RT_DRAW_READY+2
RT_ARENA_SIZE equ RT_SCRIPT_PREVIEW+SP_SIZE

; a0=first code address from a valid DOS LoadSeg chain, a1=36-byte output.
; Require the nine-hunk 0658 layout. Return 0/-1, preserve other registers.
; Validate chain length/alignment before publishing any pointer. This does
; not probe arbitrary addresses: the loader owns the valid segment memory.
timing_runtime_hunks:
 movem.l d1-d3/a0-a3,-(sp)
 suba.w #36,sp
 movea.l sp,a2
 moveq #8,d3
.walk:
 move.l a0,d0
 beq .bad
 andi.l #3,d0
 bne .bad
 move.l a0,(a2)+
 move.l -4(a0),d1
 move.l d1,d2
 andi.l #$c0000000,d2
 bne .bad
 lsl.l #2,d1
 beq .last
 movea.l d1,a0
 addq.l #4,a0 ; BPTR addresses the link word, code begins four bytes later
 dbf d3,.walk
 bra .bad
.last:
 tst.w d3
 bne .bad
 movea.l sp,a2
 moveq #8,d3
.publish:
 move.l (a2)+,(a1)+
 dbf d3,.publish
 moveq #0,d0
 bra .done
.bad:
 moveq #-1,d0
.done:
 adda.w #36,sp
 movem.l (sp)+,d1-d3/a0-a3
 rts

; a0=RT_ARENA_SIZE arena, a1=nine-pointer native hunk table, d0=50/60 field rate.
; Return 0 prepared but PAUSED, -1 invalid rate/signature. Preserve others.
; Fresh allocation only: never prepare over live or partially committed work.
; On signature failure the arena is partial/unusable and READY remains zero.
; Invalid rate changes nothing. No producer may access this arena yet.
timing_runtime_prepare:
 movem.l d1-d7/a0-a6,-(sp)
 cmpi.l #50,d0
 beq .rate
 cmpi.l #60,d0
 bne .bad
.rate:
 move.l d0,d7
 movea.l a0,a6
 move.w #RT_ARENA_SIZE/2-1,d1
.clear:
 clr.w (a0)+
 dbf d1,.clear
 lea RT_HUNKS(a6),a0
 moveq #8,d1
.hunks:
 move.l (a1)+,(a0)+
 dbf d1,.hunks
 movea.l RT_HUNKS+0(a6),a0
 lea RT_STAGES(a6),a1
 bsr motion_stages_prepare
 tst.l d0
 bne .bad
 movea.l RT_HUNKS+0(a6),a0
 lea RT_DECODER(a6),a1
 bsr world_commands_prepare
 tst.l d0
 bne .bad
 movea.l RT_HUNKS(a6),a0
 adda.l #$7a5c,a0
 lea RT_RNG(a6),a1
 lea RT_RECORD(a6),a2
 movea.l RT_HUNKS+8(a6),a3
 bsr world_rng_prepare
 tst.l d0
 bne .bad
 movea.l RT_HUNKS+0(a6),a0
 lea RT_HIT(a6),a1
 lea RT_RNG(a6),a2
 bsr world_hit_prepare
 tst.l d0
 bne .bad
 movea.l RT_HUNKS+0(a6),a0
 lea RT_EFFECTS(a6),a1
 lea RT_RNG(a6),a2
 lea RT_HEADING(a6),a3
 bsr world_effect_prepare
 tst.l d0
 bne .bad
 movea.l RT_HUNKS+0(a6),a0
 lea RT_WEAPONS(a6),a1
 lea RT_RNG(a6),a2
 lea RT_FIRE(a6),a3
 movea.l RT_HUNKS+24(a6),a4
 bsr world_weapons_prepare
 tst.l d0
 bne .bad
 movea.l RT_HUNKS+0(a6),a0
 lea RT_DAMAGE(a6),a1
 lea RT_RNG(a6),a2
 lea RT_EFFECTS(a6),a3
 lea RT_HIT(a6),a4
 movea.l RT_HUNKS+24(a6),a5
 bsr world_damage_prepare
 tst.l d0
 bne .bad
 movea.l RT_HUNKS+0(a6),a0
 lea RT_SCRIPT(a6),a1
 lea RT_RNG(a6),a2
 lea RT_HIT(a6),a3
 movea.l RT_HUNKS+24(a6),a4
 bsr world_script_prepare
 tst.l d0
 bne .bad
 movea.l RT_HUNKS+0(a6),a0
 lea RT_RESERVES(a6),a1
 bsr world_reserves_prepare
 tst.l d0
 bne .bad
 movea.l RT_HUNKS+0(a6),a0
 lea RT_PERIODIC(a6),a1
 lea RT_RNG(a6),a2
 movea.l RT_HUNKS+24(a6),a3
 bsr world_periodic_prepare
 tst.l d0
 bne .bad
 movea.l RT_HUNKS+0(a6),a0
 lea RT_CLEANUP(a6),a1
 movea.l RT_HUNKS+16(a6),a2
 bsr world_cleanup_prepare
 tst.l d0
 bne .bad
 movea.l RT_HUNKS+24(a6),a3
 adda.l #$3b88,a3
 movea.l RT_HUNKS+0(a6),a0
 lea RT_OPENING(a6),a1
 movea.l RT_HUNKS+24(a6),a2
 bsr world_start_prepare
 tst.l d0
 bne .bad
 movea.l RT_HUNKS+0(a6),a0
 lea RT_GUIDANCE(a6),a1
 movea.l RT_HUNKS+16(a6),a2
 lea RT_PENDING(a6),a3
 bsr field_guidance_prepare
 tst.l d0
 bne .bad
 movea.l RT_HUNKS(a6),a0
 lea RT_BOUNDARY(a6),a1
 bsr boundary_commands_prepare
 tst.l d0
 bne .bad
 lea RT_GUIDANCE_PRESENT(a6),a0
 movea.l RT_HUNKS(a6),a1
 movea.l RT_HUNKS+24(a6),a2
 bsr guidance_present_init
 lea RT_GUIDANCE(a6),a0
 lea RT_GUIDANCE_PRESENT(a6),a1
 bsr guidance_present_bind
 tst.l d0
 bne .bad
 movea.l RT_HUNKS+0(a6),a0
 lea RT_GROUND(a6),a1
 movea.l RT_HUNKS+24(a6),a2
 lea RT_EVENT(a6),a3
 bsr ground_deferred_prepare
 tst.l d0
 bne .bad
 movea.l RT_HUNKS+0(a6),a0
 movea.l RT_HUNKS+24(a6),a1
 lea RT_SCENE(a6),a2
 bsr scene_private_prepare
 tst.l d0
 bne .bad
 movea.l RT_HUNKS(a6),a0
 movea.l RT_HUNKS+24(a6),a1
 lea RT_VISIBILITY(a6),a2
 bsr visibility_raster_prepare
 tst.l d0
 bne .bad
 movea.l RT_HUNKS(a6),a0
 movea.l RT_HUNKS+24(a6),a1
 lea RT_TARGET(a6),a2
 bsr target_select_prepare
 tst.l d0
 bne .bad
 movea.l RT_HUNKS(a6),a0
 movea.l RT_HUNKS+16(a6),a1
 movea.l RT_HUNKS+24(a6),a2
 lea RT_VIEW(a6),a3
 bsr target_view_prepare
 tst.l d0
 bne .bad
 movea.l RT_HUNKS(a6),a0
 movea.l RT_HUNKS+24(a6),a1
 lea RT_ACTOR_PREVIEW(a6),a2
 bsr actor_preview_prepare
 tst.l d0
 bne .bad
 lea RT_ACTOR_PREVIEW(a6),a0
 move.l a0,RT_ACTOR_PRESENT+AC_PREVIEW(a6)
 move.l a0,RT_RELEASE_PRESENT+AC_PREVIEW(a6)
 movea.l RT_HUNKS(a6),a0
 movea.l RT_HUNKS+24(a6),a1
 lea RT_SCRIPT_PREVIEW(a6),a2
 bsr script_preview_prepare
 tst.l d0
 bne .bad
 movea.l RT_HUNKS(a6),a0
 adda.w #$5c04,a0
 move.l a0,RT_DRAW_ENTRY(a6)
 lea timing_runtime_actors(pc),a0
 move.l a0,RT_CONSUMER+TF_ACTOR_ENTRY(a6)
 move.l a6,RT_CONSUMER+TF_ACTOR_CONTEXT(a6)
 lea timing_runtime_target(pc),a0
 move.l a0,RT_CONSUMER+TF_TARGET_ENTRY(a6)
 move.l a6,RT_CONSUMER+TF_TARGET_CONTEXT(a6)
 lea timing_runtime_gauges(pc),a0
 move.l a0,RT_CONSUMER+TF_GAUGE_ENTRY(a6)
 move.l a6,RT_CONSUMER+TF_GAUGE_CONTEXT(a6)
 movea.l a6,a0
 bsr timing_runtime_gauges_seed
 ; Coordinate-only map entry has no OS calls; bind only the known routine.
 movea.l RT_HUNKS(a6),a0
 movea.l RT_HUNKS+24(a6),a1
 lea $3b88(a1),a1
 cmpi.w #$3039,$475a(a0)
 bne .bad
 cmpa.l $475c(a0),a1
 bne .bad
 addq.l #2,a1
 cmpi.w #$3239,$4760(a0)
 bne .bad
 cmpa.l $4762(a0),a1
 bne .bad
 cmpi.w #$4e75,$487a(a0)
 bne .bad
 lea $475a(a0),a0
 move.l a0,RT_CONSUMER+TF_MAP_ENTRY(a6)
 movea.l RT_HUNKS+16(a6),a0
 lea $1c5(a0),a0
 move.l a0,RT_CONSUMER+TF_MAP_MODE(a6)
 ; Wire arena-relative pointers from immutable offset pairs.
 lea .bindings(pc),a0
 move.w #(.bindings_end-.bindings)/4-1,d0
.bind:
 move.w (a0)+,d1
 move.w (a0)+,d2
 lea 0(a6,d2.w),a1
 move.l a1,0(a6,d1.w)
 dbf d0,.bind
 movea.l RT_HUNKS(a6),a0
 move.l a0,RT_CAPTURE+8(a6)
 lea $1068(a0),a1
 move.l a1,RT_CAPTURE+40(a6)
 move.l RT_HUNKS+8(a6),RT_CAPTURE+12(a6)
 ; Native bindings are stable addresses in the loaded hunks.
 movea.l RT_HUNKS+24(a6),a0
 move.l a0,RT_FIELD+SF_HUNK6(a6)
 lea $42f7(a0),a1
 move.l a1,RT_CONSUMER+TF_HIT_TIMER(a6)
 adda.l #$3b88,a0
 move.l a0,RT_PLAYER_READER+CP_PLAYER(a6)
 move.l a0,RT_WORLD_READER+CW_PLAYER(a6)
 move.l a0,RT_START+SW_PLAYER(a6)
 move.l a0,RT_IMPULSES+SI_PLAYER(a6)
 move.l a0,RT_PLAYER+SE_PLAYER(a6)
 move.l a0,RT_GEOMETRY+SGE_PLAYER(a6)
 move.l a0,RT_BODY+WB_PLAYER(a6)
 movea.l a0,a1
 lea RT_MODE(a6),a0
 bsr control_mode_init
 movea.l RT_HUNKS+16(a6),a0
 move.l a0,RT_FIELD+SF_HUNK4(a6)
 movea.l RT_HUNKS(a6),a0
 movea.l a0,a1
 adda.l #$af36,a1
 move.l a1,RT_WORLD_READER+CW_INDICATOR(a6)
 lea $7a44(a0),a1
 move.l a1,RT_PLAYER+SE_SINE(a6)
 movea.l a0,a1
 adda.l #$c6a0,a1
 move.l a1,RT_GEOMETRY+SGE_OBJECTS(a6)
 movea.l a0,a1
 adda.l #$a150,a1
 move.l a1,RT_CONSUMER+TF_NOTIFY(a6)
 movea.l RT_HUNKS+24(a6),a0
 lea $42f6(a0),a1
 move.l a1,RT_CONSUMER+TF_TIMER(a6)
 lea RT_CLOCK(a6),a0
 moveq #0,d0
 move.l d7,d1
 bsr clock_init
 lea RT_HISTORY(a6),a0
 moveq #0,d0
 bsr history_init
 lea RT_COMMANDS(a6),a0
 moveq #0,d0
 bsr commands_init
 lea RT_SCHEDULER(a6),a0
 lea RT_CLOCK(a6),a1
 lea RT_HISTORY(a6),a2
 lea RT_COMMANDS(a6),a3
 bsr scheduler_init
 lea RT_ENDPOINT(a6),a0
 move.l d7,d0
 moveq #0,d1
 bsr endpoint_player_init
 lea RT_SCHEDULER(a6),a0
 bsr timing_suspend
 lea RT_MODAL(a6),a0
 lea RT_SCHEDULER(a6),a1
 lea RT_BODY(a6),a2
 movea.l RT_HUNKS(a6),a3
 bsr timing_modal_prepare
 tst.l d0
 bne .bad
 move.l #1,RT_READY(a6)
 moveq #0,d0
 bra .done
.bad:
 moveq #-1,d0
.done:
 movem.l (sp)+,d1-d7/a0-a6
 rts
.bindings:
 dc.w RT_CAPTURE+16,RT_HISTORY
 dc.w RT_CAPTURE+20,RT_SAMPLE
 dc.w RT_CAPTURE+44,RT_COMMANDS
 dc.w RT_PLAYER_READER+CP_QUEUE,RT_COMMANDS
 dc.w RT_PLAYER_READER+CP_MODE,RT_MODE
 dc.w RT_WORLD_READER+CW_QUEUE,RT_COMMANDS
 dc.w RT_WORLD_READER+CW_DECODER,RT_DECODER
 dc.w RT_FIELD+SF_SCHEDULER,RT_SCHEDULER
 dc.w RT_FIELD+SF_GUIDANCE,RT_GUIDANCE
 dc.w RT_START+SW_SCHEDULER,RT_SCHEDULER
 dc.w RT_START+SW_OPENING,RT_OPENING
 dc.w RT_IMPULSES+SI_SCHEDULER,RT_SCHEDULER
 dc.w RT_IMPULSES+SI_RNG,RT_RNG
 dc.w RT_IMPULSES+SI_PACKET,RT_PACKET
 dc.w RT_IMPULSES+SI_RECORD,RT_RECORD
 dc.w RT_PLAYER+SE_OWNER,RT_ENDPOINT
 dc.w RT_PLAYER+SE_STAGES,RT_STAGES
 dc.w RT_PLAYER+SE_PACKET,RT_PACKET
 dc.w RT_PLAYER+SE_SCHEDULER,RT_SCHEDULER
 dc.w RT_PLAYER+SE_GROUND,RT_GROUND
 dc.w RT_PLAYER+SE_EVENT,RT_EVENT
 dc.w RT_GEOMETRY+SGE_SCHEDULER,RT_SCHEDULER
 dc.w RT_GEOMETRY+SGE_SCENE,RT_SCENE
 dc.w RT_BODY+WB_WEAPONS,RT_WEAPONS
 dc.w RT_BODY+WB_DAMAGE,RT_DAMAGE
 dc.w RT_BODY+WB_SCRIPT,RT_SCRIPT
 dc.w RT_BODY+WB_RESERVES,RT_RESERVES
 dc.w RT_BODY+WB_PERIODIC,RT_PERIODIC
 dc.w RT_BODY+WB_CLEANUP,RT_CLEANUP
 dc.w RT_CONSUMER+TF_SCHEDULER,RT_SCHEDULER
 dc.w RT_CONSUMER+TF_RECORD,RT_RECORD
 dc.w RT_CONSUMER+TF_FIELD_STATE,RT_FIELD
 dc.w RT_CONSUMER+TF_START,RT_START
 dc.w RT_CONSUMER+TF_PLAYER_COMMANDS,RT_PLAYER_READER
 dc.w RT_CONSUMER+TF_WORLD_COMMANDS,RT_WORLD_READER
 dc.w RT_CONSUMER+TF_MODE,RT_MODE
 dc.w RT_CONSUMER+TF_IMPULSES,RT_IMPULSES
 dc.w RT_CONSUMER+TF_ENDPOINT,RT_PLAYER
 dc.w RT_CONSUMER+TF_GEOMETRY,RT_GEOMETRY
 dc.w RT_CONSUMER+TF_BODY,RT_BODY
 dc.w RT_CONSUMER+TF_FIRE,RT_FIRE
 dc.w RT_CONSUMER+TF_HEADING,RT_HEADING
 dc.w RT_CONSUMER+TF_EFFECT,RT_EFFECTS
.bindings_end:
