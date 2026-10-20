; Native candidate collector bound to private projected scene and target state.
; Shared world model data, viewport bounds and targeting limits must be stable.
WTC_CODE_SIZE equ $13c ; +a450..+a58c
; a0=h0,a1=h4,a2=h6,a3=private scene,a4=private WT,a5=collector buffer.
; Return 0/-1, preserve others. No native writes; flush code before use.
; The resulting clone retains native collector ABI: a5=scene context.
target_collect_prepare:
 movem.l d1-d7/a0-a6,-(sp)
 suba.w #24,sp
 movem.l a0-a5,(sp)
 lea target_collect_relocs(pc),a6
 move.w #(target_collect_relocs_end-target_collect_relocs)/8-1,d7
.check:
 move.w (a6)+,d1
 move.w (a6)+,d2
 moveq #0,d3
 move.w (a6)+,d3
 addq.l #2,a6
 movea.l 0(sp,d2.w),a0
 adda.l d3,a0
 movea.l (sp),a1
 adda.l #$a450,a1
 cmpa.l 0(a1,d1.w),a0
 bne .bad
 dbf d7,.check
 cmpi.w #$3239,(a1)
 bne .bad
 cmpi.w #$4e75,WTC_CODE_SIZE-2(a1)
 bne .bad
 movea.l a1,a0
 movea.l 20(sp),a1
 move.w #WTC_CODE_SIZE/2-1,d1
.copy:
 move.w (a0)+,(a1)+
 dbf d1,.copy
 lea target_collect_relocs(pc),a6
 move.w #(target_collect_relocs_end-target_collect_relocs)/8-1,d7
.patch:
 move.w (a6)+,d1
 addq.l #4,a6
 move.w (a6)+,d2
 cmpi.w #$ffff,d2
 beq .next
 movea.l 12(sp),a0
 btst #15,d2
 beq .scene
 movea.l 16(sp),a0
 andi.w #$7fff,d2
.scene:
 adda.w d2,a0
 movea.l 20(sp),a1
 move.l a0,0(a1,d1.w)
.next:
 dbf d7,.patch
 moveq #0,d0
 bra .done
.bad:
 moveq #-1,d0
.done:
 adda.w #24,sp
 movem.l (sp)+,d1-d7/a0-a6
 rts

; Relocations: clone offset, argument stack offset (h0/h4/h6), native offset,
; destination: scene offset, $8000+WT offset, or $ffff for stable shared read.
target_collect_relocs:
 dc.w $0002,0,$6ac8,$10a4
 dc.w $0008,8,$1d72,$ffff
 dc.w $0014,0,$a9a0,$8000+WT_STATE+$0002
 dc.w $001e,0,$76e2,$1cbe
 dc.w $0028,4,$0430,$ffff
 dc.w $0032,0,$770c,$1ce8
 dc.w $003c,4,$0432,$ffff
 dc.w $0046,0,$6ac6,$10a2
 dc.w $0050,0,$768e,$1c6a
 dc.w $005c,0,$a99c,$ffff
 dc.w $0066,0,$6ac6,$10a2
 dc.w $006c,0,$a9a2,$8000+WT_STATE+$0004
 dc.w $007e,0,$5b00,$00dc
 dc.w $0084,0,$a9a4,$8000+WT_STATE+$0006
 dc.w $008e,0,$76e2,$1cbe
 dc.w $0094,0,$a998,$ffff
 dc.w $009e,0,$a99a,$ffff
 dc.w $00a8,8,$3ba2,$ffff
 dc.w $00b2,0,$a9a0,$8000+WT_STATE+$0002
 dc.w $00b8,0,$a9a0,$8000+WT_STATE+$0002
 dc.w $00be,0,$aa0a,$8000+WT_STATE+$006c
 dc.w $00c6,0,$6ac6,$10a2
 dc.w $00ce,0,$5b00,$00dc
 dc.w $00d6,0,$a9a6,$8000+WT_STATE+$0008
 dc.w $00e0,0,$a9b0,$8000+WT_STATE+$0012
 dc.w $00f8,0,$aa1e,$8000+WT_STATE+$0080
 dc.w $00fe,0,$76e2,$1cbe
 dc.w $0106,0,$770c,$1ce8
 dc.w $010e,0,$6ac6,$10a2
 dc.w $0118,0,$5a24,$ffff
 dc.w $0130,0,$aa32,$8000+WT_STATE+$0094
target_collect_relocs_end:
