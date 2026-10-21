; Private next-world-step preview of the six shared projectile/effect slots.
; No installer: the runtime must serialize world completion and certify slot
; generations before consuming these poses. No rendering or gameplay callbacks.
AP_H0 equ 0
AP_H6 equ 4
AP_UNCERTAIN equ 8 ; terrain-query slots whose height is not strictly positive
AP_SAFE equ 10 ; candidate slots only; identity certification still required
AP_MASKS equ 12 ; native BA08..BA0F
AP_SELECTED equ 20 ; native AA0A..AA15
AP_COUNTERMEASURES equ 32 ; native h6+42E8..42E9
AP_CLOSE equ 34 ; native B92C
AP_LOOKUP equ 35 ; native 9C52
AP_ACTORS equ 36 ; native C6A0..C761, including movement scratch
AP_PLAYER equ AP_ACTORS+$c2 ; player/split-object state through P+02D5
AP_CODE equ AP_PLAYER+$2d6
AP_CODE_SIZE equ $c69e-$bed4
AP_SIZE equ AP_CODE+AP_CODE_SIZE

; a0=h0,a1=h6,a2=AP_SIZE destination. Return 0/-1, preserve others.
; Validate every absolute operand before copying. Flush code before first use.
; Preparation failure leaves the destination untouched.
actor_preview_prepare:
 movem.l d1-d7/a0-a6,-(sp)
 suba.w #12,sp
 movem.l a0-a2,(sp)
 lea actor_preview_relocs(pc),a6
 move.w #(actor_preview_relocs_end-actor_preview_relocs)/8-1,d7
.check:
 move.w (a6)+,d1
 move.w (a6)+,d2
 moveq #0,d3
 move.w (a6)+,d3
 addq.l #2,a6
 movea.l 0(sp,d2.w),a0
 adda.l d3,a0
 movea.l (sp),a1
 adda.l #$bed4,a1
 cmpa.l 0(a1,d1.w),a0
 bne .bad
 dbf d7,.check
 cmpi.w #$4239,(a1)
 bne .bad
 cmpi.w #$4e75,AP_CODE_SIZE-2(a1)
 bne .bad
 movea.l 8(sp),a2
 move.l (sp),AP_H0(a2)
 move.l 4(sp),AP_H6(a2)
 clr.l AP_UNCERTAIN(a2)
 lea AP_CODE(a2),a0
 move.w #AP_CODE_SIZE/2-1,d1
.copy:
 move.w (a1)+,(a0)+
 dbf d1,.copy
 lea actor_preview_relocs(pc),a6
 move.w #(actor_preview_relocs_end-actor_preview_relocs)/8-1,d7
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
 lea actor_preview_terrain(pc),a0
.store:
 lea AP_CODE(a2),a1
 move.l a0,0(a1,d1.w)
.next:
 dbf d7,.patch
 ; Sound has no data dependency after the native impact call. The following
 ; BSET establishes its own condition flags. Never call audio from preview.
 move.w #$4e71,AP_CODE+$c3e2-$bed4(a2)
 move.w #$4e71,AP_CODE+$c3e4-$bed4(a2)
 move.w #$4e71,AP_CODE+$c3e6-$bed4(a2)
 moveq #0,d0
 bra .done
.bad:
 moveq #-1,d0
.done:
 adda.w #12,sp
 movem.l (sp)+,d1-d7/a0-a6
 rts

; a0=prepared AP,a1=committed P. Return candidate mask D0, preserve others.
; Snapshot native state, run one private native step, retain private endpoints.
; This never publishes any actor state. A caller must reject stale generations,
; changed eligibility and lifecycle epochs before using AP_SAFE/coordinates.
actor_preview_step:
 movem.l d1-d7/a0-a6,-(sp)
 moveq #0,d6
 bra actor_preview_snapshot_entry

; Same ABI, plus a2=read-only 12-byte forecast selector. Caller must certify
; candidate geometry/visibility and its epoch before choosing this entry.
; Overrides only the private dependency; never borrows native selector RAM.
actor_preview_selected_step:
 movem.l d1-d7/a0-a6,-(sp)
 move.l a2,d6
actor_preview_snapshot_entry:
 movea.l a0,a6
 movea.l a1,a0
 lea AP_PLAYER(a6),a1
 move.w #$2d6/2-1,d1
.player:
 move.w (a0)+,(a1)+
 dbf d1,.player
 movea.l AP_H0(a6),a2
 lea actor_preview_snapshots(pc),a3
 moveq #4,d7
.snapshot:
 moveq #0,d0
 move.w (a3)+,d0
 movea.l a2,a0
 adda.l d0,a0
 move.w (a3)+,d0
 lea 0(a6,d0.w),a1
 move.w (a3)+,d1
 subq.w #1,d1
.bytes:
 move.b (a0)+,(a1)+
 dbf d1,.bytes
 dbf d7,.snapshot
 tst.l d6
 beq .native_selector
 movea.l d6,a0
 lea AP_SELECTED(a6),a1
 move.l (a0)+,(a1)+
 move.l (a0)+,(a1)+
 move.l (a0),(a1)
.native_selector:
 movea.l AP_H6(a6),a0
 move.w $42e8(a0),AP_COUNTERMEASURES(a6)
 clr.l AP_UNCERTAIN(a6)
 lea AP_PLAYER(a6),a5
 lea AP_CODE(a6),a0
 jsr (a0)
 ; Certify each slot separately below; an aggregate decoy count must not
 ; freeze unrelated actors whose native step completes normally.
 moveq #0,d0
 movea.l AP_H0(a6),a0
 adda.l #$ba08,a0
 move.w (a0),d0
 and.w 4(a0),d0
 and.w AP_MASKS(a6),d0
 andi.w #63,d0
 move.w AP_UNCERTAIN(a6),d1
 not.w d1
 and.w d1,d0
 movea.l AP_H0(a6),a0
 adda.l #$c6d0,a0
 lea AP_ACTORS+$30(a6),a1
 moveq #5,d1
.slots:
 move.b 6(a0,d1.w),d2
 btst #0,d2
 bne .reject
 cmp.b 6(a1,d1.w),d2
 bne .reject
 move.b 0(a0,d1.w),d2
 cmpi.b #1,d2
 bls .reject
 ; Native decoy contact at C3BE branches to C514 without the ordinary
 ; lifetime decrement at C456, even when type/allocation remain unchanged.
 ; Requiring exactly one decrement identifies that discontinuity per slot.
 subq.b #1,d2
 cmp.b 0(a1,d1.w),d2
 bne .reject
 bra .next
.reject:
 bclr d1,d0
.next:
 dbf d1,.slots
.done:
 move.w d0,AP_SAFE(a6)
 andi.l #63,d0
 movem.l (sp)+,d1-d7/a0-a6
 rts

; Native B3B2 returns only 0/-1 after sampling a bitmap. Both are below a
; strictly positive actor height, so substituting zero is branch-equivalent.
; At zero/negative height mark the slot unsafe; its private result is unusable.
; A6 remains the preview context throughout the cloned routine.
actor_preview_terrain:
 tst.w 24(a2)
 bgt .clear
 bset d5,AP_UNCERTAIN+1(a6)
.clear:
 moveq #0,d0
 rts

actor_preview_snapshots:
 dc.w $ba08,AP_MASKS,8
 dc.w $aa0a,AP_SELECTED,12
 dc.w $b92c,AP_CLOSE,1
 dc.w $9c52,AP_LOOKUP,1
 dc.w $c6a0,AP_ACTORS,$c2

; Operand offset, source base (0=h0,4=h6), original target, private target.
; FFFF retains a read-only native operand; FFFE binds the terrain stub.
; The apparent pointer at C28A is instruction/immediate data, NOT a relocation.
actor_preview_relocs:
 dc.w $0002,0,$c752,AP_ACTORS+$b2
 dc.w $0008,0,$c75b,AP_ACTORS+$bb
 dc.w $000e,0,$c753,AP_ACTORS+$b3
 dc.w $0014,0,$c754,AP_ACTORS+$b4
 dc.w $001a,0,$c755,AP_ACTORS+$b5
 dc.w $0020,0,$c756,AP_ACTORS+$b6
 dc.w $0028,0,$c53e,AP_CODE+$66a
 dc.w $0038,0,$c53e,AP_CODE+$66a
 dc.w $0048,0,$c53e,AP_CODE+$66a
 dc.w $0050,0,$ba08,AP_MASKS+$0
 dc.w $0056,0,$ba0c,AP_MASKS+$4
 dc.w $0062,0,$c6d0,AP_ACTORS+$30
 dc.w $006a,0,$c6a0,AP_ACTORS+$0
 dc.w $0080,0,$c75c,AP_ACTORS+$bc
 dc.w $0086,0,$c75d,AP_ACTORS+$bd
 dc.w $0096,0,$c752,AP_ACTORS+$b2
 dc.w $00a0,0,$c753,AP_ACTORS+$b3
 dc.w $00c4,0,$c75d,AP_ACTORS+$bd
 dc.w $00dc,0,$aa14,AP_SELECTED+$a
 dc.w $00ea,0,$aa0a,AP_SELECTED+$0
 dc.w $0100,0,$aa0b,AP_SELECTED+$1
 dc.w $0108,0,$aa15,AP_SELECTED+$b
 dc.w $0112,0,$c654,AP_CODE+$780
 dc.w $0148,4,$42e8,AP_COUNTERMEASURES+$0
 dc.w $015c,0,$c75b,AP_ACTORS+$bb
 dc.w $016e,0,$c75d,AP_ACTORS+$bd
 dc.w $0182,4,$42e9,AP_COUNTERMEASURES+$1
 dc.w $0196,0,$c75b,AP_ACTORS+$bb
 dc.w $01a0,0,$c75c,AP_ACTORS+$bc
 dc.w $01ac,0,$c56e,AP_CODE+$69a
 dc.w $01b6,0,$c75e,AP_ACTORS+$be
 dc.w $01c0,0,$c75f,AP_ACTORS+$bf
 dc.w $01c8,0,$c760,AP_ACTORS+$c0
 dc.w $01ce,0,$ba20,$ffff
 dc.w $01d8,0,$c75f,AP_ACTORS+$bf
 dc.w $01de,0,$c75e,AP_ACTORS+$be
 dc.w $01e4,0,$c75c,AP_ACTORS+$bc
 dc.w $01ee,0,$c75d,AP_ACTORS+$bd
 dc.w $01f8,0,$ba30,$ffff
 dc.w $0202,0,$ba31,$ffff
 dc.w $020c,0,$c75b,AP_ACTORS+$bb
 dc.w $0246,0,$ba5c,$ffff
 dc.w $0252,0,$c74c,AP_ACTORS+$ac
 dc.w $025e,0,$c74e,AP_ACTORS+$ae
 dc.w $0274,0,$c74c,AP_ACTORS+$ac
 dc.w $027a,0,$c74e,AP_ACTORS+$ae
 dc.w $0284,0,$c74c,AP_ACTORS+$ac
 dc.w $028a,0,$c74e,AP_ACTORS+$ae
 dc.w $029c,0,$c74c,AP_ACTORS+$ac
 dc.w $02a2,0,$c74e,AP_ACTORS+$ae
 dc.w $02b8,0,$c74c,AP_ACTORS+$ac
 dc.w $02be,0,$c74e,AP_ACTORS+$ae
 dc.w $02d4,0,$c74c,AP_ACTORS+$ac
 dc.w $02da,0,$c74e,AP_ACTORS+$ae
 dc.w $02f4,0,$c74c,AP_ACTORS+$ac
 dc.w $02fa,0,$c74e,AP_ACTORS+$ae
 dc.w $0304,0,$c74c,AP_ACTORS+$ac
 dc.w $030a,0,$c74e,AP_ACTORS+$ae
 dc.w $032c,0,$c74c,AP_ACTORS+$ac
 dc.w $0332,0,$c74e,AP_ACTORS+$ae
 dc.w $0338,0,$c74c,AP_ACTORS+$ac
 dc.w $033e,0,$c74e,AP_ACTORS+$ae
 dc.w $0344,0,$c6a0,AP_ACTORS+$0
 dc.w $035c,0,$c748,AP_ACTORS+$a8
 dc.w $038c,0,$c748,AP_ACTORS+$a8
 dc.w $0398,0,$c750,AP_ACTORS+$b0
 dc.w $039e,0,$c742,AP_ACTORS+$a2
 dc.w $03a4,0,$c744,AP_ACTORS+$a4
 dc.w $03be,0,$b92c,AP_CLOSE
 dc.w $03cc,0,$c74c,AP_ACTORS+$ac
 dc.w $03e0,0,$c74e,AP_ACTORS+$ae
 dc.w $03f4,0,$c748,AP_ACTORS+$a8
 dc.w $0418,0,$c74c,AP_ACTORS+$ac
 dc.w $042a,0,$c74c,AP_ACTORS+$ac
 dc.w $0434,0,$c74e,AP_ACTORS+$ae
 dc.w $0446,0,$c74e,AP_ACTORS+$ae
 dc.w $0450,0,$c750,AP_ACTORS+$b0
 dc.w $0462,0,$c750,AP_ACTORS+$b0
 dc.w $0490,0,$c748,AP_ACTORS+$a8
 dc.w $04ba,0,$c56e,AP_CODE+$69a
 dc.w $04c0,0,$c61a,AP_CODE+$746
 dc.w $04dc,0,$c56e,AP_CODE+$69a
 dc.w $04e2,0,$c61a,AP_CODE+$746
 dc.w $04ec,0,$c754,AP_ACTORS+$b4
 dc.w $04f6,0,$c755,AP_ACTORS+$b5
 dc.w $04fc,0,$ba08,AP_MASKS+$0
 dc.w $0504,0,$ba08,AP_MASKS+$0
 dc.w $0510,0,$a150,$ffff
 dc.w $052c,0,$c74c,AP_ACTORS+$ac
 dc.w $0532,0,$c74e,AP_ACTORS+$ae
 dc.w $0552,0,$b3b2,$fffe
 dc.w $058c,0,$ba08,AP_MASKS+$0
 dc.w $0594,0,$ba08,AP_MASKS+$0
 dc.w $05d2,0,$ba10,$ffff
 dc.w $05e6,0,$ba54,$ffff
 dc.w $05f6,0,$c756,AP_ACTORS+$b6
 dc.w $0602,0,$c56e,AP_CODE+$69a
 dc.w $0608,0,$c742,AP_ACTORS+$a2
 dc.w $060e,0,$c744,AP_ACTORS+$a4
 dc.w $0614,0,$c746,AP_ACTORS+$a6
 dc.w $0642,0,$c75b,AP_ACTORS+$bb
 dc.w $0648,0,$c752,AP_ACTORS+$b2
 dc.w $0652,0,$b92c,AP_CLOSE
 dc.w $065e,0,$b92c,AP_CLOSE
 dc.w $06c8,0,$c760,AP_ACTORS+$c0
 dc.w $06da,0,$c760,AP_ACTORS+$c0
 dc.w $06e0,0,$c742,AP_ACTORS+$a2
 dc.w $06f2,0,$c760,AP_ACTORS+$c0
 dc.w $06f8,0,$c744,AP_ACTORS+$a4
 dc.w $0702,0,$c748,AP_ACTORS+$a8
 dc.w $070e,0,$c746,AP_ACTORS+$a6
 dc.w $071c,0,$c760,AP_ACTORS+$c0
 dc.w $072c,0,$c760,AP_ACTORS+$c0
 dc.w $0740,0,$c760,AP_ACTORS+$c0
 dc.w $0748,0,$c742,AP_ACTORS+$a2
 dc.w $074e,0,$c744,AP_ACTORS+$a4
 dc.w $0764,0,$c746,AP_ACTORS+$a6
 dc.w $0782,0,$aa0b,AP_SELECTED+$1
 dc.w $078c,0,$aa14,AP_SELECTED+$a
 dc.w $07c4,0,$9c52,AP_LOOKUP
actor_preview_relocs_end:
