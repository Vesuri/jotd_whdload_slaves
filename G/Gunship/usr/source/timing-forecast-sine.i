; Private immutable sine helper/table for forecast-only motion clones.
FS_CODE_SIZE equ 24
FS_TABLE_SIZE equ 512
FS_SIZE equ FS_CODE_SIZE+FS_TABLE_SIZE

; a0=native sine helper, a1=its expected table, a2=536-byte private buffer.
; Return 0/-3, other registers preserved. Validate before destination writes.
; Caller owns valid source buffers and flushes instruction caches afterward.
forecast_sine_prepare:
 movem.l d1/a0-a3,-(sp)
 cmpi.l #$024000ff,(a0)
 bne .bad
 cmpi.l #$d04041f9,4(a0)
 bne .bad
 cmpa.l 8(a0),a1
 bne .bad
 cmpi.l #$d0c03010,12(a0)
 bne .bad
 cmpi.l #$c1c1d080,16(a0)
 bne .bad
 cmpi.l #$48404e75,20(a0)
 bne .bad
 movea.l a2,a3
 moveq #FS_CODE_SIZE/4-1,d1
.code:
 move.l (a0)+,(a3)+
 dbf d1,.code
 move.l a3,8(a2)
 move.w #FS_TABLE_SIZE/4-1,d1
.table:
 move.l (a1)+,(a3)+
 dbf d1,.table
 moveq #0,d0
 bra .done
.bad:
 moveq #-3,d0
.done:
 movem.l (sp)+,d1/a0-a3
 rts

; a0=prepared private stages, a1=old helper, a2=new private helper.
; Validate all 42 call sites before changing any operand. Runtime/native
; stages must never be passed here. Flush caches after this construction step.
forecast_stages_bind_sine:
 movem.l d1-d3/a0-a3,-(sp)
 movea.l a0,a3
 moveq #MS_COUNT-1,d3
.validate_stage:
 lea forecast_sine_calls(pc),a0
 moveq #5,d2
.validate:
 move.w (a0)+,d1
 cmpi.w #$4eb9,0(a3,d1.w)
 bne .bad
 cmpa.l 2(a3,d1.w),a1
 bne .bad
 dbf d2,.validate
 adda.w #MP_CODE_SIZE,a3
 dbf d3,.validate_stage
 suba.l #MS_CODE_SIZE,a3
 moveq #MS_COUNT-1,d3
.bind_stage:
 lea forecast_sine_calls(pc),a0
 moveq #5,d2
.bind:
 move.w (a0)+,d1
 move.l a2,2(a3,d1.w)
 dbf d2,.bind
 adda.w #MP_CODE_SIZE,a3
 dbf d3,.bind_stage
 moveq #0,d0
 bra .done
.bad:
 moveq #-3,d0
.done:
 movem.l (sp)+,d1-d3/a0-a3
 rts
forecast_sine_calls:
 dc.w $14e,$180,$1a0,$2c6,$304,$33c
