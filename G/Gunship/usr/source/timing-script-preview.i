; Private index-5 scripted-object next pose. Native steering and word/byte
; arithmetic, with explicit stable committed terrain pixels and no RNG/damage.
; The body entry accepts supplied P+2C. Forecast entry privately executes
; the native mode/activation prefix and rejects pending modal transitions.
; Not installed. Caller serializes state and waits for bitmap DMA completion.
SP_H0 equ 0
SP_H6 equ 4
SP_BITMAP equ 8
SP_PALETTE equ 12 ; two classification bytes for the committed bitmap
SP_CLOSE equ 14 ; private native B92C
SP_TERRAIN_OR equ 15 ; private native A14C
SP_TARGET equ 16 ; private h6+157B scripted target index
SP_VALID equ 17
SP_UNKNOWN equ 18
SP_PLAYER equ 20
SP_PLAYER_SIZE equ $2d6
SP_CODE equ SP_PLAYER+SP_PLAYER_SIZE
SP_CODE_SIZE equ $a14c-$9fb0
SP_PREFIX equ SP_CODE+SP_CODE_SIZE
SP_PREFIX_SIZE equ $36
SP_SIZE equ SP_PREFIX+SP_PREFIX_SIZE+2

; a0=h0,a1=h6,a2=SP destination. Validate before writes. Return 0/-1.
; Preserve others; flush instruction cache after successful preparation.
script_preview_prepare:
 movem.l d1-d7/a0-a6,-(sp)
 suba.w #12,sp
 movem.l a0-a2,(sp)
 ; Validate every prefix word, including both relocated absolute operands.
 movea.l a0,a1
 adda.l #$9f74,a1
 lea script_preview_prefix_signature(pc),a6
 moveq #0,d1
.prefix_check:
 cmpi.w #$a,d1
 beq .query_operand
 cmpi.w #$1c,d1
 beq .flags_operand
 move.w 0(a6,d1.w),d2
 cmp.w 0(a1,d1.w),d2
 bne .bad
 addq.w #2,d1
 bra .prefix_next
.query_operand:
 movea.l (sp),a0
 adda.l #$b422,a0
 bra .prefix_operand
.flags_operand:
 movea.l 4(sp),a0
 adda.l #$395c,a0
.prefix_operand:
 cmpa.l 0(a1,d1.w),a0
 bne .bad
 addq.w #4,d1
.prefix_next:
 cmpi.w #SP_PREFIX_SIZE,d1
 blo .prefix_check
 movea.l (sp),a0
 adda.l #$8050,a0
 cmpi.l #$4a2d0053,(a0)
 bne .bad
 cmpi.l #$6f00014e,4(a0)
 bne .bad
 cmpi.l #$532d0054,8(a0)
 bne .bad
 cmpi.l #$66000146,12(a0)
 bne .bad
 lea script_preview_relocs(pc),a6
 moveq #(script_preview_relocs_end-script_preview_relocs)/8-1,d7
.check:
 move.w (a6)+,d1
 move.w (a6)+,d2
 moveq #0,d3
 move.w (a6)+,d3
 addq.l #2,a6
 movea.l 0(sp,d2.w),a0
 adda.l d3,a0
 movea.l (sp),a1
 adda.l #$9fb0,a1
 cmpa.l 0(a1,d1.w),a0
 bne .bad
 dbf d7,.check
 cmpi.w #$7005,(a1)
 bne .bad
 cmpi.l #$302d000c,$a0ca-$9fb0(a1)
 bne .bad
 cmpi.w #$4e75,SP_CODE_SIZE-2(a1)
 bne .bad
 movea.l 8(sp),a2
 move.l (sp),SP_H0(a2)
 move.l 4(sp),SP_H6(a2)
 clr.b SP_VALID(a2)
 lea SP_CODE(a2),a0
 move.w #SP_CODE_SIZE/2-1,d1
.copy:
 move.w (a1)+,(a0)+
 dbf d1,.copy
 lea script_preview_relocs(pc),a6
 moveq #(script_preview_relocs_end-script_preview_relocs)/8-1,d7
.patch:
 move.w (a6)+,d1
 addq.l #4,a6
 move.w (a6)+,d2
 cmpi.w #$ffff,d2
 beq .next
 cmpi.w #$fffe,d2
 beq .terrain
 movea.l a2,a0
 adda.w d2,a0
 bra .store
.terrain:
 lea script_preview_terrain(pc),a0
.store:
 lea SP_CODE(a2),a1
 move.l a0,0(a1,d1.w)
.next:
 dbf d7,.patch
 ; Heading has already been adjusted. Skip the RNG/damage decision and hit
 ; callback entirely. Neither owns this object's movement inputs; the native
 ; movement suffix reloads its inputs from player/object state.
 move.l #$60000038,SP_CODE+$a0ca-$9fb0(a2)
 movea.l (sp),a1
 adda.l #$9f74,a1
 lea SP_PREFIX(a2),a0
 moveq #SP_PREFIX_SIZE/2-1,d1
.prefix_copy:
 move.w (a1)+,(a0)+
 dbf d1,.prefix_copy
 move.w #$4e75,(a0)
 moveq #0,d0
 bra .done
.bad:
 moveq #-1,d0
.done:
 adda.w #12,sp
 movem.l (sp)+,d1-d7/a0-a6
 rts

; a0=prepared SP,a1=committed P,a2=stable BitMap,a3=two palette bytes.
; Return 1 candidate next pose, 0 inactive/unknown. Preserve other regs.
; Only SP_PLAYER's index-5 split coordinates/heading are candidate outputs.
; Lifetime, spawn/teleport certification and fractional publication are the
; consumer's responsibility; never publish this whole private player record.
script_preview_step:
 movem.l d1-d7/a0-a6,-(sp)
 moveq #0,d7
 bra script_preview_common

; Same ABI as body entry. Recompute native mode on private P; refuse any
; activation/countdown which would enter the modal interpreter. The prefix
; only reads native region/flag data; all of its writes target private A5.
script_preview_forecast:
 movem.l d1-d7/a0-a6,-(sp)
 moveq #1,d7
script_preview_common:
 movea.l a0,a6
 clr.b SP_VALID(a6)
 clr.w SP_UNKNOWN(a6)
 move.l a2,SP_BITMAP(a6)
 move.b (a3),SP_PALETTE(a6)
 move.b 1(a3),SP_PALETTE+1(a6)
 lea SP_PLAYER(a6),a0
 move.w #SP_PLAYER_SIZE/2-1,d1
.copy:
 move.w (a1)+,(a0)+
 dbf d1,.copy
 movea.l SP_H0(a6),a0
 adda.l #$b92c,a0
 move.b (a0),SP_CLOSE(a6)
 movea.l SP_H6(a6),a0
 move.b $157b(a0),SP_TARGET(a6)
 cmpi.b #128,SP_TARGET(a6)
 bhs .unknown
 ; Zero X is native inactivity. Check the split coordinate before execution.
 move.b SP_PLAYER+$5b(a6),d0
 or.b SP_PLAYER+$d5(a6),d0
 beq .unknown
 lea SP_PLAYER(a6),a5
 tst.w d7
 beq .body
 lea SP_PREFIX(a6),a0
 jsr (a0)
 tst.b $53(a5)
 ble .body
 cmpi.b #1,$54(a5)
 beq .unknown
 subq.b #1,$54(a5)
.body:
 lea SP_CODE(a6),a0
 jsr (a0)
 tst.w SP_UNKNOWN(a6)
 bne .unknown
 move.b #1,SP_VALID(a6)
 moveq #1,d0
 bra .done
.unknown:
 moveq #0,d0
.done:
 movem.l (sp)+,d1-d7/a0-a6
 rts

; Replacement for 7FA4. A5 is private P, A6 is SP throughout the native copy.
; Preserve the native incoming upper D0/D1 halves through word operations.
script_preview_terrain:
 movem.l a0-a1,-(sp)
 move.w $26(a5),d0
 add.w d0,d0
 add.w $1e(a5),d0
 move.w $28(a5),d1
 add.w d1,d1
 add.w $20(a5),d1
 movea.l SP_BITMAP(a6),a0
 lea SP_PALETTE(a6),a1
 bsr terrain_sample
 cmpi.l #-3,d0
 bne .done
 ; Scripted mode ORs this first result with nonzero P+2C and skips
 ; every later terrain probe. An unknown, ignored result is not a barrier.
 tst.b $2c(a5)
 bne .ignored
 move.w #1,SP_UNKNOWN(a6)
.ignored:
 moveq #0,d0 ; unknown relevant queries invalidate the final candidate
.done:
 movem.l (sp)+,a0-a1
 rts

; Operand offset, original base (0=h0,4=h6), target, private offset/sentinel.
script_preview_relocs:
 dc.w $004,0,$7b7e,$ffff
 dc.w $01a,0,$7fa4,$fffe
 dc.w $038,4,$157b,SP_TARGET
 dc.w $03e,0,$7b7e,$ffff
 dc.w $052,0,$7b7e,$ffff
 dc.w $088,0,$7ac8,$ffff
 dc.w $0c8,0,$b92c,SP_CLOSE
 dc.w $0d4,0,$a14c,SP_TERRAIN_OR
 dc.w $0e6,0,$7fa4,$fffe
 dc.w $0ec,0,$a14c,SP_TERRAIN_OR
 dc.w $0f6,0,$a14c,SP_TERRAIN_OR
 dc.w $13c,0,$7a5c,$ffff
 dc.w $150,0,$7d92,$ffff
 dc.w $15c,0,$7a44,$ffff
 dc.w $170,0,$7a44,$ffff
 dc.w $196,0,$7bd0,$ffff
script_preview_relocs_end:

script_preview_prefix_signature:
 dc.w $302d,$0000,$322d,$0002,$4eb9,0,0,$6700,$0022
 dc.w $4a2d,$0053,$6600,$001a,$1039,0,0,$0240,$0003
 dc.w $6700,$000c,$7001,$1b40,$0053,$1b40,$0054
 dc.w $1b42,$002c
