; Foreground ordering for one already-delivered field. Not installed.
; All bindings prepared, stable and nonoverlapping; caller owns batch delivery,
; lifecycle commands, script modals, rendering and explicit fault recovery.
TF_SCHEDULER equ 0
TF_RECORD equ 4
TF_FIELD_STATE equ 8
TF_START equ 12
TF_PLAYER_COMMANDS equ 16
TF_WORLD_COMMANDS equ 20
TF_MODE equ 24
TF_IMPULSES equ 28
TF_ENDPOINT equ 32
TF_GEOMETRY equ 36
TF_BODY equ 40
TF_FIRE equ 44
TF_HEADING equ 48
TF_NOTIFY equ 52
TF_TIMER equ 56
TF_PHASE equ 60 ; 0 fresh, 1 player commands, 2 world commands, 3 executing,
                ; 4 complete, 5 script modal, 6 flight ended, 7 fault
TF_TICK equ 62
TF_FIELD equ 64
TF_EFFECT equ 68 ; optional recurring effect clone (runtime always binds)
TF_HIT_TIMER equ 72 ; native hit countdown byte, paired with TF_EFFECT
TF_MAP_ENTRY equ 76 ; optional native coordinate-only entry
TF_MAP_MODE equ 80 ; native panel mode byte (1 = map)
TF_SIZE equ 84

; a0=TF, d0=command budget per reader (1..128). Preserve other registers.
; Return 0 field complete, 1 world complete, 2 retained command boundary,
; 3 script modal, 4 flight ended, -2 command budget, -1 latched failure,
; -3 invalid admission. Budget/boundary returns resume the same reader phase.
; Native side effects are never rolled back or automatically retried on fault.
timing_flight_consume:
 movem.l d1-d7/a0-a6,-(sp)
 movea.l a0,a6
 tst.l d0
 beq .bad
 cmpi.l #128,d0
 bhi .bad
 move.l d0,d7
 movea.l TF_SCHEDULER(a6),a5
 cmpi.w #7,TF_PHASE(a6)
 beq .fault
 cmpi.w #1,TS_STATE(a5)
 bne .bad
 movea.l TF_RECORD(a6),a0
 move.l TR_FIELD(a0),d1
 cmp.l TS_FIELD(a5),d1
 bne .bad
 move.l TR_COMMAND(a0),d2
 cmp.l TS_COMMAND(a5),d2
 bne .bad
 move.w TF_PHASE(a6),d0
 beq .new
 cmpi.w #4,d0
 beq .next
 cmp.l TF_FIELD(a6),d1
 bne .bad
 cmpi.w #1,d0
 beq .player_commands
 cmpi.w #2,d0
 beq .world_commands
 bra .bad
.next:
 cmp.l TF_FIELD(a6),d1
 beq .bad
.new:
 move.l d1,TF_FIELD(a6)
 move.w #3,TF_PHASE(a6)
 movea.l TF_ENDPOINT(a6),a1
 movea.l SE_PLAYER(a1),a2
 move.w $0c(a2),d0
 addq.w #1,d0
 move.w d0,TF_TICK(a6)
 movea.l SE_PACKET(a1),a1
 bsr controls_from_history
 tst.l d0
 bne .fault
 movea.l TF_FIELD_STATE(a6),a0
 bsr scheduled_field_vbl_state
 tst.l d0
 bmi .fault
 tst.w TS_DUE(a5)
 beq .commands
 movea.l TF_START(a6),a0
 bsr scheduled_world_start
 tst.l d0
 bne .fault
.commands:
 move.w #1,TF_PHASE(a6)
.player_commands:
 movea.l a5,a0
 movea.l TF_PLAYER_COMMANDS(a6),a1
 move.l d7,d0
 bsr command_phase_player
 tst.l d0
 bne .command_result
 tst.w TS_DUE(a5)
 beq .motion
 move.w #2,TF_PHASE(a6)
.world_commands:
 movea.l a5,a0
 movea.l TF_WORLD_COMMANDS(a6),a1
 move.l d7,d0
 bsr command_phase_world_before_player
 tst.l d0
 bne .command_result
 movea.l TF_MODE(a6),a0
 movea.l TF_ENDPOINT(a6),a1
 movea.l SE_PLAYER(a1),a1
 bsr control_mode_check
 tst.l d0
 bne .fault
 movea.l TF_IMPULSES(a6),a0
 bsr scheduled_motion_impulses
 tst.l d0
 bmi .fault
.motion:
 move.w #3,TF_PHASE(a6)
 movea.l TF_ENDPOINT(a6),a0
 movea.l TF_RECORD(a6),a1
 moveq #0,d0
 move.w TF_TICK(a6),d0
 bsr scheduled_endpoint_ground_step
 move.l d0,d6
 ; Even a post-publication producer fault must commit the published event.
 movea.l TF_ENDPOINT(a6),a0
 tst.w SE_COMMITTED(a0)
 beq .motion_result
 movea.l SE_EVENT(a0),a0
 tst.b GD_READY(a0)
 beq .motion_result
 movea.l TF_NOTIFY(a6),a1
 movea.l TF_TIMER(a6),a2
 bsr ground_deferred_commit
 tst.l d0
 bmi .fault
.motion_result:
 tst.l d6
 bmi .fault
 ; Recalculate from this field's committed pose, independent of map draws.
 move.l TF_MAP_ENTRY(a6),d0
 beq .map_done
 movea.l TF_MAP_MODE(a6),a1
 cmpi.b #1,(a1)
 bne .map_done
 movea.l d0,a1
 movem.l d1-d7/a0-a6,-(sp)
 jsr (a1)
 movem.l (sp)+,d1-d7/a0-a6
.map_done:
 tst.l d6
 beq .field_complete
 movea.l a5,a0
 movea.l TF_FIRE(a6),a1
 bsr world_fire_prepare
 tst.l d0
 bne .fault
 movea.l TF_ENDPOINT(a6),a0
 movea.l SE_PLAYER(a0),a0
 movea.l TF_HEADING(a6),a1
 move.b $35(a0),(a1)
 clr.b 1(a1)
 ; The old renderer spawned this effect while the hit timer was nonzero.
 ; Admit it once per deadline using the committed player and deadline RNG.
 ; TF_PHASE is already executing; failure cannot replay the constructor.
 move.l TF_EFFECT(a6),d0
 beq .effect_done
 movea.l TF_HIT_TIMER(a6),a1
 tst.b (a1)
 beq .effect_done
 movem.l a5-a6,-(sp)
 movea.l a0,a5
 movea.l d0,a1
 jsr (a1)
 movem.l (sp)+,a5-a6
.effect_done:
 movea.l TF_BODY(a6),a0
 clr.w WB_PHASE(a0) ; new deadline admitted once, never a retry
 movea.l TF_GEOMETRY(a6),a1
 bsr world_scene_body_step
 tst.l d0
 beq .world_complete
 cmpi.l #2,d0
 beq .modal
 cmpi.l #3,d0
 bne .fault
 move.w #6,TF_PHASE(a6)
 bsr .ack
 tst.l d0
 bmi .fault
 moveq #4,d0
 bra .done
.world_complete:
 bsr .ack
 tst.l d0
 bmi .fault
 move.w #4,TF_PHASE(a6)
 moveq #1,d0
 bra .done
.field_complete:
 move.w #4,TF_PHASE(a6)
 moveq #0,d0
 bra .done
.modal:
 move.w #5,TF_PHASE(a6)
 moveq #3,d0
 bra .done
.command_result:
 cmpi.l #-2,d0
 beq .done
 cmpi.l #2,d0
 beq .done
.fault:
 move.w #7,TF_PHASE(a6)
 moveq #-1,d0
 bra .done
.bad:
 moveq #-3,d0
.done:
 movem.l (sp)+,d1-d7/a0-a6
 rts
.ack:
 movea.l a5,a0
 bra scheduler_world_done
