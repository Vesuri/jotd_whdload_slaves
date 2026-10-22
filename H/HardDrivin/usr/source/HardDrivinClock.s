; Arcade race timing, CUSTOM5=1 (SPS 0126 only, any CUSTOM1). The native VBL
; clocks run at about half (time left) and three quarters (lap time, which
; depends on the interrupted X flag) of real time. These clocks count real
; PAL time exactly and follow the arcade's rules: time left starts at the
; start and is capped at the starting time; after zero the engine stays cut
; and the race ends below 3.4 MPH or 10 s later, while a checkpoint reached
; meanwhile still counts; a crash and its replay slow time left to 5/16 and
; leave the lap time out; the off-road limit is 11 s. The arcade's limits
; (MAME's operator defaults, difficulty presets from the options menu) are
; doubled for the longer Amiga course. The Phantom race has no time limit.
; Outside races the native clocks run unchanged.

; A PAL field is 142102 CPU clocks at 7093790 Hz: 2 + 2262/709379 hundredths.
CLOCK_FIELD_DIVISOR equ 709379
CLOCK_FIELD_REMAINDER equ 2262
; Times in hundredths of a second: the arcade's limits, doubled.
CLOCK_CHECKPOINT_SPEED equ 6400	; arcade 32 s (speed route), 29 s (stunt)
CLOCK_CHECKPOINT_STUNT equ 5800
CLOCK_CHAMPION equ 18600		; the arcade's Phantom Photon, 1:33.00
CLOCK_HANDICAP equ 1000		; qualifying allowance, arcade 5 s (EASY)
CLOCK_HANDICAP_STEP equ 100	; arcade 0.5 s more after each game that did not qualify
CLOCK_HANDICAP_MAX equ 2000	; arcade 10 s
; Per incident, not scaled.
CLOCK_OFFROAD equ 1100		; the arcade's 2750 ticks counted as 11 s
CLOCK_GRACE equ 1000		; the race ends 10 s after zero
CLOCK_STOP_SPEED equ 12		; |G($9928)| below this is below 3.4 MPH

CS_FRACTION equ 0		; long, field remainder in 1/709379 hundredth
CS_OVERTIME equ 4		; long, hundredths past zero
CS_CHAMPION equ 8		; long, hundredths
CS_NATIVE_LAP equ 12		; long, native $2c4c
CS_NATIVE_LEFT equ 16		; long, native $2c8a
CS_CRASH equ 20			; word, sixteenths of a hundredth
CS_HANDICAP equ 22		; word, hundredths
CS_FINISHES equ 24		; word
CS_PENDING equ 26		; word, hundredths held while an award writes time left
CS_EXPIRED equ 28		; byte
CS_BUSY equ 29			; byte
CS_PLAYED equ 30		; byte
CS_QUALIFIED equ 31		; byte
CS_SIZE equ 32

; The slave's globals lie beyond PC-relative range from this module: reach
; them from a local base with assembler-constant offsets.
_clock_install:
	movem.l d0-d1/a0-a3,-(a7)
	cmpi.l #$11a4e,d0
	bne .done
	lea _clock_install(pc),a3
	movea.l a3,a0
	adda.l #_ct_ct5-_clock_install,a0
	tst.l (a0)
	beq .done
	movea.l a3,a0
	adda.l #_code_start-_clock_install,a0
	movea.l (a0),a1
	lea _clock_state(pc),a0
	move.l a1,d0
	addi.l #$2c4c,d0
	move.l d0,CS_NATIVE_LAP(a0)
	addi.l #$2c8a-$2c4c,d0
	move.l d0,CS_NATIVE_LEFT(a0)
	move.l #CLOCK_CHAMPION,CS_CHAMPION(a0)
	move.w #CLOCK_HANDICAP,CS_HANDICAP(a0)
	lea _clock_patches(pc),a0
	movea.l a3,a2
	adda.l #_resload-_clock_install,a2
	movea.l (a2),a2
	jsr resload_Patch(a2)
.done:
	movem.l (a7)+,d0-d1/a0-a3
	rts

_clock_patches:
	PL_START
	; PERF_RANGE CUSTOM5 $0005a $000e: VBL clocks
	PL_PSS $5a,_clock_vbl,8
	; PERF_RANGE CUSTOM5 $07d94 $0006: start button
	PL_PS $7d94,_clock_button_start
	; PERF_RANGE CUSTOM5 $0887a $0006: race set-up, time left
	PL_PS $887a,_clock_race_init
	; PERF_RANGE CUSTOM5 $08880 $000e: race set-up, off-road deadline
	PL_PSS $8880,_clock_offroad,8
	; PERF_RANGE CUSTOM5 $092fc $005e: checkpoint award
	PL_PS $92fc,_clock_checkpoint
	PL_S $9302,$935a-$9302
	; PERF_RANGE CUSTOM5 $093fa $005e: finish award
	PL_PS $93fa,_clock_finish
	PL_S $9400,$9458-$9400
	; PERF_RANGE CUSTOM5 $0b178 $000e: off-road deadline
	PL_PSS $b178,_clock_offroad,8
	; PERF_RANGE CUSTOM5 $104e4 $0006: automatic start, time left
	PL_PS $104e4,_clock_auto_start
	; PERF_RANGE CUSTOM5 $10edc $0014: time out
	PL_PSS $10edc,_clock_expired,14
	; PERF_RANGE CUSTOM5 $11878 $000e: Phantom off-road deadline
	PL_PSS $11878,_clock_offroad,8
	; PERF_RANGE CUSTOM5 $1196c $0006: Phantom win, champion's lap
	PL_PS $1196c,_clock_champion
	PL_END

; Replaces the gate test and both native clock calls in the VBL. D0/A0/A1 are
; free, as they were for the native routines.
_clock_vbl:
	movem.l d1-d2,-(a7)
	lea _clock_state(pc),a0
	moveq #2,d1
	move.l CS_FRACTION(a0),d0
	addi.l #CLOCK_FIELD_REMAINDER,d0
	cmpi.l #CLOCK_FIELD_DIVISOR,d0
	blo.s .whole
	subi.l #CLOCK_FIELD_DIVISOR,d0
	addq.w #1,d1
.whole:
	move.l d0,CS_FRACTION(a0)
	tst.b -$16cf(a4)		; G($e931) Phantom race
	beq.s .race
	; the arcade resets the qualifying allowance for the championship lap
	move.w #CLOCK_HANDICAP,CS_HANDICAP(a0)
	bra.s .gate
.race:
	tst.b -$522c(a4)		; G($add4) race
	beq.s .native
.gate:
	tst.b -$6a13(a4)		; G($95ed) clocks running
	bne.s .running
	tst.b -$5229(a4)		; G($add7) the instant replay stops them
	bne.s .crash
	bra.s .done
.running:
	tst.b -$5221(a4)		; G($addf) started: before, only the start countdown
	beq.s .lap
	tst.b -$69fa(a4)		; G($9606) crash
	bne.s .crash
	tst.b -$5229(a4)
	bne.s .crash
	lea -$6870(a4),a1
	bsr _clock_bcd_add
	tst.b -$16cf(a4)
	bne.s .done
	bsr _clock_left
	bra.s .done
.crash:
	; lap time stopped, time left at 5/16 (the arcade's 5 ticks of 16)
	tst.b -$16cf(a4)
	bne.s .done
	move.w d1,d0
	lsl.w #2,d0
	add.w d1,d0
	add.w CS_CRASH(a0),d0
	moveq #15,d1
	and.w d0,d1
	move.w d1,CS_CRASH(a0)
	lsr.w #4,d0
	move.w d0,d1
	beq.s .done
	bsr _clock_left
	bra.s .done
.lap:
	lea -$6870(a4),a1
	bsr _clock_bcd_add
	bra.s .done
.native:
	tst.b -$6a13(a4)
	beq.s .done
	movea.l CS_NATIVE_LAP(a0),a1
	jsr (a1)
	movea.l _clock_state+CS_NATIVE_LEFT(pc),a1
	jsr (a1)
.done:
	movem.l (a7)+,d1-d2
	rts

; D1.l = hundredths off time left, A0 = state. Below zero time left stays 0
; and the time past zero is counted. While an award writes time left, the
; hundredths wait for the next field.
_clock_left:
	tst.b CS_BUSY(a0)
	beq.s .apply
	add.w d1,CS_PENDING(a0)
	rts
.apply:
	add.w CS_PENDING(a0),d1
	clr.w CS_PENDING(a0)
.part:
	cmpi.l #9,d1
	bls.s _clock_left_digit
	move.l d1,-(a7)
	moveq #9,d1
	bsr.s _clock_left_digit
	move.l (a7)+,d1
	subi.l #9,d1
	bra.s .part

; D1.l = 0..9 hundredths.
_clock_left_digit:
	tst.b CS_EXPIRED(a0)
	bne.s .past
	lea -$6868(a4),a1		; G($9798) time left
	cmp.l (a1),d1
	bhi.s .expire
	bra _clock_bcd_sub
.expire:
	; time left is below 10 hundredths here, where BCD equals binary
	sub.l (a1),d1
	clr.l (a1)
	st -$6864(a4)			; G($979c) time out
	st CS_EXPIRED(a0)
	move.l d1,CS_OVERTIME(a0)
	rts
.past:
	add.l d1,CS_OVERTIME(a0)
	rts

; Adds D1.b (0..9) hundredths to the BCD clock 00MMSSHH at A1. Uses D0/D2.
_clock_bcd_add:
	moveq #0,d2
	move.b 3(a1),d0
	move.w #0,ccr
	abcd d1,d0
	bcs.s .carry
	move.b d0,3(a1)
	rts
.carry:
	move.b d0,3(a1)			; keeps X
	move.b 2(a1),d0
	abcd d2,d0
	cmpi.b #$60,d0
	bcs.s .seconds
	move.b d2,2(a1)
	move.b 1(a1),d0
	move.w #$10,ccr
	abcd d2,d0
	move.b d0,1(a1)
	rts
.seconds:
	move.b d0,2(a1)
	rts

; Subtracts D1.b (0..9) hundredths from the BCD clock at A1, which holds at
; least D1. Uses D0/D2.
_clock_bcd_sub:
	moveq #0,d2
	move.b 3(a1),d0
	move.w #0,ccr
	sbcd d1,d0
	bcs.s .borrow
	move.b d0,3(a1)
	rts
.borrow:
	move.b d0,3(a1)			; keeps X
	move.b 2(a1),d0
	sbcd d2,d0
	bcc.s .seconds
	moveq #$59,d0
	move.b d0,2(a1)
	move.b 1(a1),d0
	move.w #$10,ccr
	sbcd d2,d0
	move.b d0,1(a1)
	rts
.seconds:
	move.b d0,2(a1)
	rts

; D0.l = BCD 00MMSSHH -> D0.l = hundredths.
_clock_from_bcd:
	movem.l d1-d3,-(a7)
	move.l d0,d3
	moveq #0,d1
	swap d0
	move.b d0,d1
	bsr.s .binary
	mulu.w #6000,d1
	move.l d1,d0
	move.w d3,d1
	lsr.w #8,d1
	bsr.s .binary
	mulu.w #100,d1
	add.l d1,d0
	moveq #0,d1
	move.b d3,d1
	bsr.s .binary
	add.l d1,d0
	movem.l (a7)+,d1-d3
	rts
.binary:
	move.w d1,d2
	lsr.w #4,d2
	mulu.w #10,d2
	andi.w #15,d1
	add.w d2,d1
	rts

; D0.l = hundredths (0..599999) -> D0.l = BCD 00MMSSHH.
_clock_to_bcd:
	movem.l d1-d3,-(a7)
	divu.w #6000,d0
	move.w d0,d1
	bsr.s .bcd
	moveq #0,d3
	move.b d1,d3
	clr.w d0
	swap d0
	divu.w #100,d0
	move.w d0,d1
	bsr.s .bcd
	lsl.l #8,d3
	move.b d1,d3
	swap d0
	move.w d0,d1
	bsr.s .bcd
	lsl.l #8,d3
	move.b d1,d3
	move.l d3,d0
	movem.l (a7)+,d1-d3
	rts
.bcd:
	andi.l #$ffff,d1
	divu.w #10,d1
	move.l d1,d2
	swap d2
	lsl.w #4,d1
	or.w d2,d1
	rts

; A1 = the arcade's time preset for the options menu's difficulty G($add5)
; (1 EASY, 2 MEDIUM, 3 HARD): starting time, then extended play for the
; first, second and later finishes.
_clock_preset:
	move.l d0,-(a7)
	moveq #0,d0
	move.b -$522b(a4),d0
	subq.w #1,d0
	cmpi.w #2,d0
	bls.s .row
	moveq #0,d0
.row:
	lsl.w #3,d0
	lea _clock_presets(pc),a1
	adda.w d0,a1
	move.l (a7)+,d0
	rts

; D0.l = bonus in hundredths. Time below zero is charged against it; time
; left never exceeds the starting time.
_clock_award:
	movem.l d0-d1/a0-a1,-(a7)
	lea _clock_state(pc),a0
	st CS_BUSY(a0)
	tst.b CS_EXPIRED(a0)
	beq.s .add
	move.l CS_OVERTIME(a0),d1
	clr.l CS_OVERTIME(a0)
	sub.l d1,d0
	bgt.s .recovered
	neg.l d0
	move.l d0,CS_OVERTIME(a0)
	clr.l -$6868(a4)
	st -$6864(a4)
	bra.s .done
.recovered:
	sf CS_EXPIRED(a0)
	move.l d0,d1
	moveq #0,d0
	bra.s .sum
.add:
	move.l d0,d1
	move.l -$6868(a4),d0
	bsr _clock_from_bcd
.sum:
	add.l d1,d0
	bsr _clock_preset
	moveq #0,d1
	move.w (a1),d1
	cmp.l d1,d0
	bls.s .store
	move.l d1,d0
.store:
	bsr _clock_to_bcd
	move.l d0,-$6868(a4)
.done:
	sf CS_BUSY(a0)
	movem.l (a7)+,d0-d1/a0-a1
	rts

; Replaces the checkpoint bonus (34 s less the difficulty) and its addition.
_clock_checkpoint:
	move.l d0,-(a7)
	move.l #CLOCK_CHECKPOINT_SPEED,d0
	tst.b -$66b0(a4)		; G($9950) stunt road
	beq.s .award
	move.l #CLOCK_CHECKPOINT_STUNT,d0
.award:
	bsr _clock_award
	move.l (a7)+,d0
	rts

; Replaces the finish bonus and its addition. The native code has already
; checked the lap against the qualifying time; it restarts the lap clock next.
_clock_finish:
	movem.l d0-d1/a0-a1,-(a7)
	lea _clock_state(pc),a0
	tst.b -$6362(a4)		; G($9c9e) qualified in this game
	beq.s .bonus
	st CS_QUALIFIED(a0)
.bonus:
	bsr _clock_preset
	move.w CS_FINISHES(a0),d1
	cmpi.w #2,d1
	bls.s .extended
	moveq #2,d1
.extended:
	add.w d1,d1
	moveq #0,d0
	move.w 2(a1,d1.w),d0
	addq.w #1,CS_FINISHES(a0)
	bsr _clock_award
	; an armed off-road deadline follows the lap clock to zero
	move.l -$5228(a4),d0		; G($add8)
	beq.s .done
	bsr _clock_from_bcd
	move.l d0,d1
	move.l -$6870(a4),d0
	bsr _clock_from_bcd
	sub.l d0,d1
	bgt.s .rebase
	moveq #1,d1
.rebase:
	move.l d1,d0
	bsr _clock_to_bcd
	move.l d0,-$5228(a4)
.done:
	movem.l (a7)+,d0-d1/a0-a1
	rts

; Replaces time left = G($af12) (1:45.99) at race set-up. Also sets the
; qualifying time G($9794) (shown until the player qualifies) and the
; champion's lap G($af00).
_clock_race_init:
	movem.l d0-d1/a0-a1,-(a7)
	lea _clock_state(pc),a0
	clr.l CS_OVERTIME(a0)
	sf CS_EXPIRED(a0)
	clr.w CS_FINISHES(a0)
	clr.w CS_CRASH(a0)
	clr.w CS_PENDING(a0)
	tst.b CS_PLAYED(a0)
	beq.s .first
	tst.b CS_QUALIFIED(a0)
	bne.s .first
	move.w CS_HANDICAP(a0),d0
	addi.w #CLOCK_HANDICAP_STEP,d0
	cmpi.w #CLOCK_HANDICAP_MAX,d0
	bls.s .handicap
	move.w #CLOCK_HANDICAP_MAX,d0
.handicap:
	move.w d0,CS_HANDICAP(a0)
.first:
	st CS_PLAYED(a0)
	sf CS_QUALIFIED(a0)
	bsr _clock_set_left
	move.l CS_CHAMPION(a0),d0
	move.l d0,d1
	bsr _clock_to_bcd
	move.l d0,-$5100(a4)		; G($af00)
	moveq #0,d0
	move.w CS_HANDICAP(a0),d0
	add.l d1,d0
	bsr _clock_to_bcd
	move.l d0,-$686c(a4)		; G($9794)
	movem.l (a7)+,d0-d1/a0-a1
	rts

; Time left = the starting time.
_clock_set_left:
	movem.l d0/a1,-(a7)
	bsr _clock_preset
	moveq #0,d0
	move.w (a1),d0
	bsr _clock_to_bcd
	move.l d0,-$6868(a4)
	movem.l (a7)+,d0/a1
	rts

; Replaces time left = G($af12) when the start countdown runs out.
_clock_auto_start:
	bra _clock_set_left

; Replaces G($addf) = $ff. Both clocks start here, as at the arcade's green
; light, unless the countdown already started the race.
_clock_button_start:
	tst.b -$5221(a4)
	bne.s .started
	st -$5221(a4)
	clr.l -$6870(a4)
	bra _clock_set_left
.started:
	rts

; Replaces deadline += $1099 (10.99, without a seconds carry) via $2c14.
_clock_offroad:
	move.l d0,-(a7)
	move.l -$5228(a4),d0
	bsr _clock_from_bcd
	addi.l #CLOCK_OFFROAD,d0
	bsr _clock_to_bcd
	move.l d0,-$5228(a4)
	move.l (a7)+,d0
	rts

; Replaces the race loop's time-out test, which stopped both clocks and ended
; the race when the speed reached 0.
_clock_expired:
	tst.b -$6864(a4)
	beq.s .done
	move.l d0,-(a7)
	move.w -$66d8(a4),d0		; G($9928) speed
	bpl.s .speed
	neg.w d0
.speed:
	cmpi.w #CLOCK_STOP_SPEED,d0
	blo.s .end
	move.l _clock_state+CS_OVERTIME(pc),d0
	cmpi.l #CLOCK_GRACE,d0
	blo.s .keep
.end:
	clr.b -$522c(a4)		; G($add4)
.keep:
	move.l (a7)+,d0
.done:
	rts

; Replaces G($af00) = lap clock after a Phantom win: the new champion's lap.
_clock_champion:
	move.l d0,-(a7)
	move.l a0,-(a7)
	move.l -$6870(a4),d0
	move.l d0,-$5100(a4)
	bsr _clock_from_bcd
	lea _clock_state(pc),a0
	move.l d0,CS_CHAMPION(a0)
	movea.l (a7)+,a0
	move.l (a7)+,d0
	rts

; Arcade presets EASY, MEDIUM, HARD ($3A3D8 in the arcade ROM), doubled.
_clock_presets:
	dc.w 19200,9600,9400,9200
	dc.w 18000,8800,8800,9000
	dc.w 16800,8600,8600,8800

	CNOP 0,4
_clock_state:
	ds.b CS_SIZE
	EVEN
