; Native lifecycle/display command adapter. Caller suspends sampling before
; blocking UI and owns command acknowledgement and post-command rebase.
; Do not invoke twice for one retained command. No queue cursors changed here.
BC_SIZE equ 4 ; native +04ed4 decoder entry

; a0=validated 0658 hunk 0, a1=four-byte binding.
; Validate ordinary and nonlocal return boundaries before publishing.
; Return 0/-1, preserving others. No native writes or cache flush required.
boundary_commands_prepare:
 move.l a0,-(sp)
 lea $4ed4(a0),a0
 cmpi.l #$0c470045,(a0)
 bne .bad
 cmpi.l #$584f70ff,$18(a0) ; +04eec drops inner return, then MOVEQ -1
 bne .bad
 cmpi.w #$4e75,$1c(a0)
 bne .bad
 cmpi.w #$4e75,$460(a0)
 bne .bad
 move.l a0,(a1)
 moveq #0,d0
 bra .done
.bad:
 moveq #-1,d0
.done:
 movea.l (sp)+,a0
 rts

; a0=player, a1=prepared binding, a2=native hunk 6 input context,
; d0.w=full accepted key/modifier word.
; Return 0 completed, 4 flight ended, -3 not a boundary/invalid binding.
; Preserve non-result registers. Execute the native primary/return path,
; including its yaw tail where reached.
; Enhanced key 12 retires only the old speed toggle; its yaw tail remains.
boundary_command_step:
 movem.l d1-d7/a0-a6,-(sp)
 move.w d0,d7
 bsr control_command_class
 cmpi.l #CC_BOUNDARY,d0
 bne .bad
 move.l (a1),d0
 beq .bad
 movea.l d0,a1
 cmpi.w #12,d7
 beq .retired
 movea.l a0,a5
 movea.l a2,a4
 move.l a0,-(sp)
 bsr .invoke
 movea.l (sp)+,a5
 tst.b $18(a5)
 beq .normal
 moveq #4,d0
 bra .done
.retired:
 bsr control_target_tail
.normal:
 moveq #0,d0
 bra .done
.bad:
 moveq #-3,d0
.done:
 movem.l (sp)+,d1-d7/a0-a6
 rts
.invoke:
 ; Two return addresses reproduce +04e3c's call into +04ed4.
 ; The $0833 path drops this JSR's return and returns straight to the
 ; outer caller. Pause/Esc first drops its own saved sound pointer.
 jsr (a1)
 rts

; a0=paused command queue, a1=original eight-byte retained player head.
; Call once AFTER native boundary completion, with both readers excluded.
; Mark execution for both readers without advancing either cursor or changing
; the caller's copy. They re-peek and acknowledge the marked record normally.
; Return 1 marked, -3 invalid/stale/already-marked/active/faulted. Preserve others.
; The lifecycle owner must retain its own execution phase across mark failure:
; a rejection is never permission to replay the native command.
boundary_command_mark:
 movem.l d1-d3/a0-a3,-(sp)
 tst.w CQ_ACTIVE(a0)
 bne .bad
 tst.w CQ_FAULT(a0)
 bne .bad
 tst.w 6(a1)
 bne .bad
 move.w CQ_WRITE(a0),d1
 sub.w CQ_PLAYER(a0),d1
 beq .bad
 cmpi.w #CQ_CAPACITY,d1
 bhi .bad
 move.w CQ_PLAYER(a0),d2
 sub.w CQ_WORLD(a0),d2
 cmpi.w #CQ_CAPACITY,d2
 bhi .bad
 add.w d1,d2
 cmpi.w #CQ_CAPACITY,d2
 bhi .bad
 move.w CQ_PLAYER(a0),d2
 andi.w #CQ_CAPACITY-1,d2
 lsl.w #3,d2
 lea CQ_RECORDS(a0),a2
 adda.w d2,a2
 move.l (a1),d3
 cmp.l (a2),d3
 bne .bad
 move.l 4(a1),d3
 cmp.l 4(a2),d3
 bne .bad
 moveq #0,d0
 move.w 4(a1),d0
 bsr control_command_class
 cmpi.l #CC_BOUNDARY,d0
 bne .bad
 move.w #CQ_BOUNDARY_DONE,6(a2)
 moveq #1,d0
 bra .done
.bad:
 moveq #-3,d0
.done:
 movem.l (sp)+,d1-d3/a0-a3
 rts
