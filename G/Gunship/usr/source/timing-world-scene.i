; Committed-player geometry check. Standalone, not installed.
; Requires presentation (native_camera_build) and scene-private.
; a0=authoritative native player, a1=prepared private scene workspace,
; a2=committed 36-byte world-object coordinate vector.
; Return 0 clear / 1 flight end / -1 invalid binding; preserve other registers.
; On a positive native plane result, sets player +18 to 1 as +05846 does.
; Zero preserves the existing end byte. Does not perform cleanup or acknowledge
; a world tick. Caller must run once at the world boundary after field motion
; commits and route a positive result to flight-end cleanup before more world
; work. Shared scene inputs must remain stable. Never pass predicted poses.
world_scene_check:
 movem.l d1/a0-a5,-(sp)
 movea.l a0,a4
 movea.l a1,a5
 movea.l a2,a3
 move.l SC_H6(a5),d0
 beq .bad
 addi.l #$3b88,d0
 cmp.l a4,d0
 bne .bad
 suba.w #12,sp
 movea.l sp,a2
 bsr native_camera_build
 movea.l a5,a0
 movea.l sp,a1
 movea.l a3,a2
 bsr scene_private_step
 adda.w #12,sp
 tst.l d0
 ble .done
 move.b #1,$18(a4)
 bra .done
.bad:
 moveq #-1,d0
.done:
 movem.l (sp)+,d1/a0-a5
 rts
