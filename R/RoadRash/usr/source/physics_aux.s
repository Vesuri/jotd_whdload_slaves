; Copy AI dispatch and hot acceleration helpers after the movement/code copy.
; Called only after CUSTOM2 and CPU/Fast selection, before entering the game.
; Native data/table addresses stay unchanged. Cross-copy relative calls resolve
; directly; the remaining external calls use native JMP stubs. Each span keeps
; an explicit native fallthrough target. See simulation-timing.md for the audit.
	IFD VERIFY_C_PHYSICS_AUX_CONTROL
	IFND VERIFY
	FAIL "Auxiliary physics control requires VERIFY"
	ENDC
	ENDC
step_physics_aux_init:
 lea $8d2c0,a0
 lea aux_8d2c0(pc),a1
 move.w #775,d0
.copy_8d2c0:
 move.w (a0)+,(a1)+
 dbf d0,.copy_8d2c0
 lea $8dd66,a0
 lea aux_8dd66(pc),a1
 move.w #130,d0
.copy_8dd66:
 move.w (a0)+,(a1)+
 dbf d0,.copy_8dd66
 lea $8e166,a0
 lea aux_8e166(pc),a1
 move.w #183,d0
.copy_8e166:
 move.w (a0)+,(a1)+
 dbf d0,.copy_8e166
 lea $8da5c,a0
 lea aux_8da5c(pc),a1
 move.w #86,d0
.copy_8da5c:
 move.w (a0)+,(a1)+
 dbf d0,.copy_8da5c
 lea aux_8d2c0(pc),a0
 move.w #aux_8dd66+$0-(aux_8d2c0+$36),$36(a0)
 lea aux_8d2c0(pc),a0
 move.w #aux_to_90b8e-(aux_8d2c0+$94),$94(a0)
 lea aux_8d2c0(pc),a0
 move.w #aux_to_90b7c-(aux_8d2c0+$a8),$a8(a0)
 lea aux_8d2c0(pc),a0
 move.w #aux_8dd66+$0-(aux_8d2c0+$13c),$13c(a0)
 lea aux_8d2c0(pc),a0
 move.w #aux_to_8d940-(aux_8d2c0+$15e),$15e(a0)
 lea aux_8d2c0(pc),a0
 move.w #aux_to_8dfc8-(aux_8d2c0+$170),$170(a0)
 lea aux_8d2c0(pc),a0
 move.w #aux_to_8db40-(aux_8d2c0+$188),$188(a0)
 lea aux_8d2c0(pc),a0
 move.w #aux_8e166+$ec-(aux_8d2c0+$194),$194(a0)
 lea aux_8d2c0(pc),a0
 move.w #aux_8dd66+$0-(aux_8d2c0+$1aa),$1aa(a0)
 lea aux_8d2c0(pc),a0
 move.w #aux_to_8d940-(aux_8d2c0+$1c2),$1c2(a0)
 lea aux_8d2c0(pc),a0
 move.w #aux_to_8dfc8-(aux_8d2c0+$1ce),$1ce(a0)
 lea aux_8d2c0(pc),a0
 move.w #aux_to_8db40-(aux_8d2c0+$1da),$1da(a0)
 lea aux_8d2c0(pc),a0
 move.w #aux_8e166+$ec-(aux_8d2c0+$368),$368(a0)
 lea aux_8d2c0(pc),a0
 move.w #aux_8dd66+$0-(aux_8d2c0+$37e),$37e(a0)
 lea aux_8d2c0(pc),a0
 move.w #aux_8e166+$ec-(aux_8d2c0+$404),$404(a0)
 lea aux_8d2c0(pc),a0
 move.w #aux_8dd66+$0-(aux_8d2c0+$41a),$41a(a0)
 lea aux_8d2c0(pc),a0
 move.w #aux_to_8d9e2-(aux_8d2c0+$468),$468(a0)
 lea aux_8d2c0(pc),a0
 move.w #aux_to_8d940-(aux_8d2c0+$52c),$52c(a0)
 lea aux_8d2c0(pc),a0
 move.w #aux_to_8d91c-(aux_8d2c0+$54c),$54c(a0)
 lea aux_8d2c0(pc),a0
 move.w #aux_to_8d940-(aux_8d2c0+$568),$568(a0)
 lea aux_8d2c0(pc),a0
 move.w #aux_to_8d91c-(aux_8d2c0+$588),$588(a0)
 lea aux_8d2c0(pc),a0
 move.w #aux_to_8d940-(aux_8d2c0+$5a2),$5a2(a0)
 lea aux_8d2c0(pc),a0
 move.w #aux_to_8d91c-(aux_8d2c0+$5c2),$5c2(a0)
 lea aux_8d2c0(pc),a0
 move.w #aux_to_8d940-(aux_8d2c0+$5d8),$5d8(a0)
 lea aux_8d2c0(pc),a0
 move.w #aux_to_8d91c-(aux_8d2c0+$5f8),$5f8(a0)
 lea aux_8dd66(pc),a0
 move.w #aux_to_8de6c-(aux_8dd66+$26),$26(a0)
 lea aux_8da5c(pc),a0
 move.w #aux_to_8db0a-(aux_8da5c+$24),$24(a0)
 lea aux_8da5c(pc),a0
 move.w #aux_to_8db0a-(aux_8da5c+$58),$58(a0)
 lea aux_8da5c(pc),a0
 move.w #aux_to_8db0a-(aux_8da5c+$7a),$7a(a0)
 lea aux_8da5c(pc),a0
 move.w #aux_to_8db0a-(aux_8da5c+$9e),$9e(a0)
 IFD VERIFY_C_PHYSICS_AUX_CONTROL
 bra.w .done
 ELSE
 nop
 nop
 ENDC
 lea aux_8d2c0+$0(pc),a0
 move.w #$4ef9,$8d2c0
 move.l a0,$8d2c2
 lea aux_8d2c0+$14a(pc),a0
 move.w #$4ef9,$8d40a
 move.l a0,$8d40c
 lea aux_8d2c0+$1ae(pc),a0
 move.w #$4ef9,$8d46e
 move.l a0,$8d470
 lea aux_8d2c0+$226(pc),a0
 move.w #$4ef9,$8d4e6
 move.l a0,$8d4e8
 lea aux_8dd66+$0(pc),a0
 move.w #$4ef9,$8dd66
 move.l a0,$8dd68
 lea aux_8e166+$0(pc),a0
 move.w #$4ef9,$8e166
 move.l a0,$8e168
 lea aux_8e166+$ec(pc),a0
 move.w #$4ef9,$8e252
 move.l a0,$8e254
 lea aux_8da5c+$0(pc),a0
 move.w #$4ef9,$8da5c
 move.l a0,$8da5e
.done:
 lea step_physics_aux_init(pc),a2
 suba.l #step_physics_aux_init-_resload,a2
 move.l (a2),a2
 jsr (resload_FlushCache,a2)
 rts
 cnop 0,2
aux_8d2c0:
 ds.b 1552
 jmp $8d8d0
 cnop 0,2
aux_8dd66:
 ds.b 262
 jmp $8de6c
 cnop 0,2
aux_8e166:
 ds.b 368
 jmp $8e2d6
 cnop 0,2
aux_8da5c:
 ds.b 174
 jmp $8db0a
aux_to_8d91c:
 jmp $8d91c
aux_to_8d940:
 jmp $8d940
aux_to_8d9e2:
 jmp $8d9e2
aux_to_8db0a:
 jmp $8db0a
aux_to_8db40:
 jmp $8db40
aux_to_8de6c:
 jmp $8de6c
aux_to_8dfc8:
 jmp $8dfc8
aux_to_90b7c:
 jmp $90b7c
aux_to_90b8e:
 jmp $90b8e
