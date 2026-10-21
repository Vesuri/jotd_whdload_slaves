# TFX on 68040: performance and correctness plan

## Goal

The newest intact TFX build running as fast as possible on an A1200 with a 68040,
using the 040's own FPU, with development-leftover palette glitches fixed. Existing
68020/030/060 behaviour must not regress; 68060 gets no specific work.

Target machine: A1200, Apollo 1240 (68040 at 40 MHz, FPU), 32 MB fast RAM on the
card, Kickstart 3.1, WHDLoad 20.1.

## Findings this plan rests on

- No intact 68040-specific executable is known. The CU Amiga CD #15 launcher refers to a
  `TFX.040` that is not on the CD; its 1995 integer build (`tfx.exe`, 709968 bytes) and
  the 1997 `tfx.strip`/`tfx.030` betas are damaged at disk-block level. `tfx.strip` has
  `tfx.020`'s code layout and reloc table, so it adds nothing.
- `tfx.020` (571008 bytes, built Dec 16 1997) is the newest intact build and the target.
  It is a 68881 build. Static census of its code hunk: 252 instructions the 040 FPU
  does not implement (146 `FINTRZ`, 93 `FMOVECR`, about 13 transcendental). The slave
  replaces 62 trace-found sites; the rest trap into FPSP.
- Hunk Wizard merged its hunks, so the slave forces the whole data hunk ($182C8) and BSS
  ($270FC) into chip RAM. The symbol build (`TFX.040`, 599152 bytes) shows the
  original layout: only about 150 KB was chip (hunks 2, 4, 7, 8, 9, 10).
- paraj's v2.0/2.1 rendering rework is complete only for plain `TFX`. `tfx.020` has
  the line/box/sprite parts but not the fills (`gouraud_fill`, `texture_fill`,
  `normal_fill`), the fast-RAM data relocation, the max-objects sort fix, the double
  missile fire fix or the uncapped modes.
- `TFX.040` carries 3332 symbols (`_SetPal`, `_DiffSetPal`, `@Fade…`, `_davespal`,
  `_colour_override`, …), usable to name `tfx.020` routines. The 1994 bug report on
  CD #15 lists "colours mess up" (bugs 30, 67) as unresolved.

Addresses below are offsets into the game's hunks, as in the slave's patch lists.

## Steps

Each step ends with its exit check. Performance numbers come only from the fixed
window of step 4 on the named machine; no claim without a measurement.

### 1. Build the unmodified slave and FPSP

- Local build wrapper in `tmp/dev/` with explicit include paths (WHDLoad dev tree, NDK);
  do not change `options.mk`.
- Build `TFX.slave`, `fpsp040` and `fpsp060`. The Makefile's `fpsp` target names
  `fp.s`/`code.s`, which no longer exist; build from `code040.s`/`code060.s` locally and
  fix the Makefile as its own small commit.
- Exit: rebuilt slave and FPSP boot the game like the shipped files.

### 2. Run harness on the target machine

- FS-UAE through `fsuae_common.sh`, configured as the target machine: A1200 AGA,
  68040 + FPU at 40 MHz, 32 MB 32-bit fast RAM, Kickstart 3.1, WHDLoad 20.1.
  FS-UAE's 040 timing is approximate, so emulator numbers are for A/B comparison;
  absolute fps comes from the real machine (step 14).
  Regression configurations: A1200/020, A1200/030 + FPU, A1200/060.
- Debugger attached, screenshots, own-PID process control.
- Reproducible flight: "start action mode" (C4 bit 4) plus a recorded input tape.
- Exit: two boots give the same screenshots and game state at the same frame.

Harness evidence: `tmp/dev/docs/replay-flight.md`. The recorded action flight gives
identical screenshots at four swap checkpoints on 020, 030 + FPU, 040 and 060.
040/060 also reproduce all captured game-hunk bytes. On 020/030, five absolute timer
values differ by one vblank; translating the clock origin makes every captured byte
equal. The user accepted this specific clock-origin mismatch on 2026-10-20, completing
step 2. Use the explicit `--clock-relative` comparison for the accepted baseline.
The harness retains separate raw and clock-relative results; this acceptance does
not extend to other state differences or waive step 3's counter/trace validation.

### 3. Frame counter

- Count the actual presentation path and vblanks; log per frame. The default renderer
  patches `tfx.020:$019fc` to `do_swap_screen`, which calls `_SetPage`/`_SetLogbase`
  directly. It bypasses `@ThreeScreenSwap` (`$3f99e`), so that routine alone is not a
  counter for the default path. Validate the swap-call checkpoint against publication.
- Obtain a full instruction trace from a backend and PC window that cover the loaded
  code. The current native 040 MMU captures contain screenshots/DMA but no instruction
  records, and the default 24-bit profiler window excludes the harness's Z3 code.
- Exit: counter agrees with a full trace over the fixed window.

Completed: `tmp/dev/docs/frame-counter.md`. Read-only breakpoints at the actual
`_SetPage` COP1LC write (`$4c474`) and vblank increment (`$4d2de`) agree with a
full 040 MMU dispatch trace: eight publications and 16 vblanks in the fixed
`[2,18)` flight-relative vblank window. All eight bitplanes fetch from the selected
buffer in the next field after each publication. The swap request can precede
publication by a vblank; count the write, not `$019fc`, for frame timing.
A private local emulator build supplies instruction order across Z3 addresses;
its dispatch records have no instruction costs and cannot supply step 5 percentages.
The shared emulator, slave and game remain unchanged.

### 4. Baseline matrix

- On A1200/040, measure the fixed window for: `TFX` new rendering, `TFX` original
  rendering, `tfx.020` (current slave), `TFX.FPU`, `TFX.040`. Repeat `TFX` and
  `tfx.020` on A1200/020.
- Exit: fps table and reproduction commands in `tmp/dev/docs/`. Decision recorded:
  confirm `tfx.020` as the base, and the gap it must close to plain `TFX`.

Completed: `tmp/dev/docs/baseline-matrix.md`. Two cold boots per measured row,
using the recorded flight inputs and the fixed `[2,252)` vblank window:

| Configuration | Executable / rendering | Publications / 250 vblanks | Nominal PAL fps |
|---|---|---:|---:|
| 040 timing model, 40 MHz requested | TFX, new | 59 | 11.8 |
| 040 timing model, 40 MHz requested | TFX, original | 34 | 6.8 |
| 040 timing model, 40 MHz requested | tfx.020 | 57 | 11.4 |
| 040 timing model, 40 MHz requested | TFX.FPU | 73 | 14.6 |
| 040 timing model, 40 MHz requested | Installed TFX.040 beta | 73 | 14.6 |
| 020, 14.18758 MHz, no FPU | TFX, new | 18 | 3.6 |
| 020, 14.18758 MHz, no FPU | tfx.020 forced | unavailable | unavailable |

These are emulator A/B figures, not Apollo hardware FPS. The MMU core ignores
the requested frequency for timing; the matrix uses the playbook's frequency-sensitive
040 NOMMU configuration, with live CPU/cache metadata and a verified frequency control.
All measured rows repeat their totals and screenshots; cadence and raw-state differences
remain explicit in the report, without extending step 2's state-mismatch acceptance.
The installed 599152-byte TFX.040 beta runs; it is distinct from the damaged candidates
and is not a native-040 build. Forced tfx.020 without an FPU aborts before flight.
Keep tfx.020 as the newest intact base: this fixture needs 3.5% more throughput to
match plain TFX, or 28.1% to match the older FPU builds. No game/slave code changed.

### 5. Profile `tfx.020` on the 040

- Instruction profile of the fixed window, grouped by routine.
- Instrument separately: FPSP entries per frame by opcode and site; chip-RAM data
  accesses; cache flush calls per frame (the game flushes caches to cope with its SMC);
  share of time in rendering, maths and game logic.
- Exit: report naming every hot region and its cost.

Completed: `tmp/dev/docs/profile-040.md`. A private read-only observer covers the
frequency-sensitive NOMMU loop and all loaded addresses. Per-PC costs sum exactly
to the fixed window's scheduler time; two cold boots produce byte-identical
profiles. Observation on/off gives identical events, screenshots and all captured
game-hunk bytes. The report includes every region above 0.5%, the complete routine
region table, per-frame FPSP sites, chip data accesses and cache-flush counts.

Correction to step 4: its default emulator configuration handled unsupported FPU
instructions without trapping. Target-040 experiments must explicitly enable
`fpu_no_unimplemented`. With trapping enabled, tfx.020 still presents 57 frames,
but enters FPSP 2,394 times: 42 per frame at six transcendental sites. There are
no FINTRZ/FMOVECR traps or cache flush calls in this window. Other FPU matrix rows
have not yet been remeasured with strict trapping; their ranking is provisional.

Largest self regions: ScanFillDown 14.83%, slave screen copy 12.51%, masked sprite
merge 8.71%, Project 5.95%, shape-command region 5.73%, and SuperShape view dispatch
5.29%. Chip data traffic is 1,032,912 reads and 1,249,307 writes. Functional shares
and remaining small unclassified regions are explicit in the report; step 6 must
validate symbol names and boundaries. Costs include the emulator's synthetic
instruction padding and are not hardware-accurate 040/FPU timings. The game,
slave, FPSP, shared emulator and 060 code path are unchanged.

### 6. Name `tfx.020` routines

- Transfer `TFX.040` symbols to `tfx.020` by function matching (Ghidra scripts in the
  shared environment); map paraj's `TFX` patch targets to `tfx.020`.
- Exit: symbol map covering the profile's hot routines and every routine paraj patched.

Completed: `tmp/dev/docs/symbol-map.md`. The accepted map covers all 30 hot regions
and all 60 active address-bearing rows (57 distinct sites) in the plain-TFX main
and 060 patch lists. It separates 723 unique complete relocation-masked symbol
spans from reviewed semantic matches and explicitly local names for unnamed
helpers. Short normalized instruction matches remain candidates only. Shared
Ghidra exporters audit 37 selected function entries; symbol spans and profiling
intervals are not assumed to be complete function bodies.

Step 7 targets: sort hooks `$5efbe` and `$5f03e`, depth array `$5bf16`, object count
`$5bf10`; duplicate-fire hook `$4e080`, skipping to `$4e0a6`. The two sort hook
sequences match the integer build byte-for-byte. Later ports require adapters:
GouraudFill at `$4f840` has a different ABI, the frame limit is a MOVEQ at `$1abfe`,
and delta time moved from A4+500 to A4-$ba4. The six observed FPSP sites belong to
`@tan`, `@sin`, `@cos`, `@atan2`, `@atan` and `@asin`. Input hashes, coverage,
original-byte guards and negative controls pass. No executable/slave code changed;
runtime correctness and performance validation remain mandatory for each port.

### 7. Port missing correctness fixes

- Sort fix when objects are at maximum (`do_sort`, `depth_ptr`), double missile fire
  from joystick, and anything else in `pl_020` absent from `pl_fpu_new`.
- Exit: each fix reproduced and verified on `tfx.020`; no fps change expected.

Completed correctness ports: `7a9ea96` (sort) and `18f4c42` (joystick fire).
Evidence and reproduction: `tmp/dev/docs/correctness-fixes.md`. The original
full-array sort corrupts guarded depth/index fixtures; the port passes 39
boundary, insertion and ABI cases across 040, 030+FPU and 060. Actual distinct
missile allocations prove the duplicate launch before the input fix and one
launch per press afterward, with keyboard firing and original rendering retained.
The remaining missing plain-TFX patches belong to memory placement (step 8) or
rendering/uncapped-mode adapters (step 10), not this correctness port.

Strict 040 timing remains 57 publications per 250 vblanks (nominal PAL 11.4 fps,
emulator A/B only). Publication cadence and final flight state can differ from
the old sort. Extra cold-boot image checks repeat, but full-state replay gates
do not all pass: clock-origin and other captured-state differences remain
explicit in the report. No new mismatch waiver or complete state equivalence is
claimed. Step 8 must establish a controlled scene/time comparison before using
identical screenshots as its exit check; matching frame totals alone is insufficient.

### 8. Undo the chip-RAM merge

- From the `TFX.040` hunk layout and step 6 symbols, list what truly needs chip RAM
  (bitplanes, sprites, copper lists, blitter sources, audio).
- Load the merged data/BSS into fast RAM, place the chip-only objects in a chip
  allocation and relocate references to them (as `reloc_2_0_020` does for `TFX`).
  Replace the `AllocMem` chip override for the new path.
- Exit: identical screenshots in the fixed window; fps measured.

Completed: `a539348`; report and reproduction in `tmp/dev/docs/chip-placement.md`.
The new-rendering 040 path loads merged data/BSS into fast RAM and copies DMA
objects into a 141,152-byte chip allocation, saving about 115 KiB of chip payload.
All 62 relocation sites are verified; 156 CPU-only references, including palette
snapshots and screen selectors, stay in fast RAM. Original rendering and
020/030/060 retain their existing placement.

Strict 040 throughput rises from 57 to 73 publications in the fixed 250-vblank
window (+28.07%, nominal PAL 11.4 to 14.6 fps; emulator A/B, not hardware FPS).
Two candidate runs match events, final image and all three hunk dumps. Five
controlled baseline/candidate screenshots match with fixed simulation timesteps,
synchronous resolved input and CPU-held capture after actual publication; all
eight displayed bitplanes are validated. These fixtures are absent from normal
builds and timing runs. Uncontrolled old/new final images differ with cadence.
Normal replay pairs repeat images on all four CPUs; 020/040/060 match raw state,
while 030 has a two-vblank clock-origin difference. No new state waiver is claimed.

### 9. Remove FPU traps from the hot path

- Generate patches for all `FINTRZ` and `FMOVECR` sites from disassembly rather than
  traces; check every constant used.
- Replace the transcendental sites (or the library wrappers they sit in) with 040-native
  routines of the precision the game needs; compare against FPSP results over the
  inputs seen in play.
- Keep FPSP installed as the safety net.
- Exit: zero FPSP entries during the fixed window; identical state at the window's end,
  or differences explained; fps measured.

Completed: `ee06330` and `29a6c7e`; report `tmp/dev/docs/native-fpu.md`.
All 146 FINTRZ and 93 FMOVECR sites are generated from guarded disassembly.
Native 040 helpers replace the six hot transcendental sites; FPSP remains the
safety net, CUSTOM5 still disables the patches, and the 060 list is unchanged.
Two strict fixed-window runs have zero FPSP entries, versus 3,066 after step 8.
Throughput remains 73 publications/250 vblanks (no measured emulator fps gain).

Static helpers pass 2,294 value/status cases including all FPCR precision/rounding
modes. Native maths passes 5,196 cases against an independent 80-digit oracle;
maximum scaled per-call error is 2.54e-16. Five controlled screenshots match.
Same-build enabled/disabled end states differ only in the intentional opcodes,
four clock fields and 20 floating-point cells; maximum accumulated absolute
numeric difference after 57 updates is 7.276e-12. All other game-hunk bytes match.
These are explained arithmetic differences, not bit-identical replacements.

Ordinary 020/030/060 replay images match; live 060 FPU patches equal step 8.
The 040 MMU pair has a three-vblank clock-origin shift and a differing final
checkpoint image; that repeatability gate remains failed, with no new waiver.
The strict timing pair matches events/images but retains clock and in-progress
sprite scratch differences. Hardware speed/accuracy still needs step 14.

### 10. Port paraj's rendering to `tfx.020`

- Fills (`@GouraudFill`, `_TextureFill`, `ScanFillDown`), fast-RAM render buffer and
  chunky-to-planar, `start_frame`, then the uncapped and 1-frame options.
- Exit: per-routine equivalence checks, frame screenshots equal to the original
  rendering, fps measured.

Completed: `fb0137f`, `94fb17c`, `e006c99`, `6ec951e`; report and reproduction in
`tmp/dev/docs/rendering-port.md`. The 040-only list ports Gouraud/texture fills onto
the existing fast planar buffer and scanline C2P pipeline, plus uncapped/one-frame
options with the new timestep and FPU-stack ABI. The equivalent generic flat-fill
port measured 72 publications versus 73 with original ScanFillDown, so the faster
original is retained. Original rendering remains selectable; 060 behavior is unchanged.

Per-routine checks cover 436 initial fill cases (including flat), 180 final selected
fill cases, 592 original-blitter line cases, 259 box cases and 41 timestep/stack/zoom
cases. Independent pixel models verify non-empty fill and clipped-box outputs.
Two pre-existing CPU-line errors (endpoint count and stipple rotation/repetition)
and omitted one-pixel-wide boxes are fixed only on the new 040 path. Five controlled
frames now match original rendering exactly, in all bitplanes and PNG screenshots.
All four ordinary CPU replay pairs repeat every screenshot and captured hunk byte.
CPU/combined-option audits confirm the off path, bit-6 precedence and unchanged
030/060 option handling; all 245 inspected 060 FPU sites equal step 9.

Default, uncapped and one-frame modes each repeat 73 publications/250 vblanks with
zero FPU exceptions: no measured throughput gain over step 9 (emulator A/B only).
Default also repeats raw state. The uncapped pair has a one-vblank clock shift and
eight bytes of inactive audio-queue tail residue; one-frame differs only by a
one-vblank clock shift. These are documented, not a new state-mismatch waiver.
Normal and CHIP_ONLY builds pass; both FPSP binaries and pristine inputs are unchanged.

### 11. 68040-specific tuning

- With SMC fixed, drop the per-frame cache flushes that are no longer needed; run fast
  RAM in copyback.
- `MOVE16` for line-aligned copies to chip, 040 scheduling of the hottest loops,
  FPU values kept in registers.
- Exit: each change A/B-measured; keep only measurable wins.

Completed with no retained code change; report `tmp/dev/docs/tuning-040.md`.
A fresh baseline exactly repeats step 10's profile, final image and all captured
hunk bytes. Fast RAM copyback is already requested, and the new-rendering window
has no cache flushes to remove. Original-rendering SMC protection is retained.

Three same-build screen-copy A/B pairs (aligned MOVE16, MOVEM, longer longword
unroll) each produce 73 publications/250 vblanks on both sides, with zero FPSP
entries. Candidate instructions are verified executed; all three are rejected
for no measurable throughput gain. Their uncontrolled final images/state differ;
no routine equivalence or new mismatch waiver is claimed. Current-symbol cost
reporting and three negative controls pass. The final slave and both FPSP files
are byte-identical to step 10, preserving its CPU regression artifact. These are
emulator A/B results; Apollo hardware tuning remains dependent on step 14.

### 12. Palette glitches

- Reported symptom: a stray yellow colour on the A1200/040 (details not remembered).
  Reproduce on A1200/040 and compare with A1200/020: screenshot menus, briefing,
  cockpit, external views and fades; search frames for unexpected yellow entries in
  the palette or copper list.
- Suspects: `_SetPal`/`_DiffSetPal` writing colour registers outside vertical blank (a
  race that a faster CPU exposes), debug palettes or overrides (`_davespal`,
  `_greenpal`, `_colour_override`), bugs 30/67, fade routines.
- Exit: root cause written down, fix verified with screenshots on both machines.

Investigation started; exit not passed. See `tmp/dev/docs/palette-investigation.md`.
The yellow symptom has not been reproduced in the captured enrolment, menus,
training introduction, aircraft/loadout selection or sampled flight views.
Eighteen stable flight samples on 040/020 match all 256 hardware palette entries
to the game's live snapshot. Two complete traced 040 SetPal calls write all
512 RGB entries to the correct banks/nibbles. These observations do not rule out
an intermittent or hardware-only fault; not every requested 020 view was verified,
and the mission-briefing route remains incomplete. No root cause or palette fix
is claimed. The slave and both FPSPs remain byte-identical to step 11.
A more specific trigger or hardware capture is needed to direct the next search.
The user also could not reproduce it and reported that a debug executable may
have been in use (2026-10-20). The affected executable is unknown; this is a
possible explanation, not a confirmed cause. Retain the current palette code
unless a reproducible faulty build or hardware capture becomes available.

### 13. Selection, options and regression

- Auto-select `tfx.020` with the new path on 040 + FPU. Leave 020/030/060 selection and
  behaviour unchanged unless measured better; gate new patches by CPU and options.
- Exit: every executable and option boots on 020, 030, 040, 060 configurations.

Completed: `b0a1139`; report `tmp/dev/docs/selection-regression.md`.
Automatic mode now selects newest `tfx.020` on full 040+FPU. Explicit choices and
020/030/060 automatic selection remain unchanged. Eight baseline selections,
49 supported flight/option cases (three actual publications each), and 16
intro/menu/configuration startup cases pass. Each advertised executable/option
is covered, including original rendering, FPS display, combined frame limits
and CUSTOM5; this is not every possible option-mask combination.

All 239 static FPU replacements are verified on automatic 040, with original
instructions restored by CUSTOM5. All 245 inspected 060 FPU sites are unchanged.
The seven unchanged automatic choices reproduce their baseline checkpoint PNG;
no full-state equivalence or new performance result is claimed. Normal and
CHIP_ONLY builds pass; both FPSPs are byte-identical to the baseline.
The no-FPU 020 supports integer TFX: forcing the three FPU builds gives the
expected Line 1111 exceptions, explicitly excluded from successful boots.
Palette code remains unchanged; step 12 is still unreproduced.

### 14. Real hardware and release

- User runs the build on the A1200/040. Update the ReadMe. Commit one coherent feature
  per commit under the fork rules, then open the pull request.

## Open questions

- Where the yellow colour appears; step 12 searches for it.

## Further optimization: 20 fps target

Benchmark audit: the earlier debugger-switched A/B controls below used a code
write on the disabled side only. The private debugger's `tfxmem` implementation
writes back/invalidates CPU caches, so matching game-hunk bytes did not establish
matching cache state. Those counts remain historical observations; their precise
attribution to each optimization requires remeasurement with symmetric setup.
Native arithmetic/buffer tests and displayed-image comparisons are unaffected.
The corrected profiler writes the selected instructions at the same address and
length on BOTH sides before timing, and checks startup registers as well as game
hunks. Revalidation is in progress; do not treat the earlier percentages as
cache-balanced results or as hardware speed measurements.

Target a sustained average of 20 presented frames/s on the Apollo 1240/40 with
vsync retained and no reduction in scene detail or simulation work. Hardware
validation is required; emulator throughput is an A/B development measure.
The latest fixed-window baseline is 73 publications/250 PAL vblanks (14.6 nominal
fps); 100 publications would reach 20 nominal fps, requiring 37% more throughput.
A 20 fps average across two- and three-refresh frames requires equal numbers of
each (50 ms mean frame duration). Mostly three-refresh frames yield closer to
16.67 fps. Track the interval distribution as well as the aggregate rate.

1. Recheck the current build and presentation path. Distinguish COP1LC publication
   from visible buffer adoption; the fast renderer currently calls SetPage without
   an explicit sync wait. Establish cadence, simulation timing and display safety
   before changing synchronization. Retain the existing fixed-window comparison,
   then extend promising measurements to at least 2,000 fields.
2. Optimize expensive exact-output drawing first: masked sprite merge, then flat
   spans and geometry preparation. Use measured routine costs and completed-call
   comparisons; keep original rendering and other CPU paths available unchanged.
3. For each candidate, audit hook boundaries, run native original/replacement
   comparisons with guards and edge cases, and perform same-build enabled/disabled
   timing. Reject changes with no useful measured gain. Verify controlled scenes,
   native-FPU trap counts, CPU/option gates and normal/CHIP_ONLY builds before
   committing each accepted change.
4. Measure the retained build on hardware, including longer representative
   cockpit/external flights and frame-interval distributions. Report achieved
   rates and remaining bottlenecks; do not equate an emulator result with the
   20 fps hardware goal or change the emulator to manufacture that result.

First retained improvement: new-renderer 040 screen copies use two 64,000-byte
fast-RAM shadows and write only changed 16-byte blocks to chip RAM. First use
copies everything; entering PlayLevel invalidates both shadows. Allocation failure
retains the full copy. Original rendering and 020/030/060 do not allocate shadows.

The final same-build, same-seed 2,000-field pair presents 546 frames disabled and
578 enabled (+5.86%, nominal PAL 13.65 to 14.45 fps). Its original 250-field prefix
improves from 73 to 77 (14.6 to 15.4). These are emulator comparisons, not hardware
rates or a claim that 20 fps is reached. Logical chip writes fall from 8,967,382 to
3,108,888 in the longer window; these are CPU operations, not physical bus cycles.

Verification: 80 native copy/history/guard cases, four checker negative controls,
114 in-game completed-copy checks across cockpit and view-change fixtures, and ten
complete 64,000-byte displayed-plane/PNG comparisons against the disabled path.
Cached copies match both chip buffers before all 110 tested reuses. All four CPU
gates and 040 original rendering reach flight; all 245 inspected 060 FPU sites are
unchanged. Normal/CHIP_ONLY builds have no relocation records. Evidence and tools:
`tmp/dev/docs/optimization-20fps.md`, `tmp/dev/tmp/opt20/`.

The longer window newly reaches FETOX at tfx.020:$51682 (204 FPSP entries disabled,
142 enabled). The earlier zero-trap result applies only to its short window.
Investigate this additional site separately. Hardware measurement is postponed
because the user does not currently have the Amiga available; optimization remains
in progress and the 20 fps hardware goal is unverified.

Native exponential follow-up: the extended flight's FETOX at $51682 now uses
040 arithmetic for finite |x| <= 64 with FPCR=0. Other arguments and modes retain
the original instruction/FPSP. This follows a recorded operand baseline; the
read-only observer reproduces the prior build's complete non-math capture.

Verification: 1,248 cases against an independent 80-digit exponential oracle
(maximum relative error 1.539e-16), 726 exact non-default-mode comparisons, and
four checker negative controls. A controlled 400-update flight executes 440
exponentials, with identical input sequences and seven identical complete
64,000-byte displayed buffers and PNGs. Two double-precision state cells differ
by rounding; five existing clock values differ by two fields. All remaining
hunk bytes match apart from the intentional instruction patch. This is not a
bit-identical simulation-state claim or a new clock-equivalence waiver.

The same-build 2,000-field timing pair remains 578 frames (14.45 nominal fps)
with the helper off or on, while FPSP entries fall from 142 to zero. Retain this
change for native 040 maths, without claiming an additional emulator speed gain.
Exceptional inputs outside the bounded native range may still use FPSP.

Final 040/CUSTOM5/060 gates pass; all 246 inspected 060 FPU sites remain
unchanged. Normal and CHIP_ONLY builds have no relocation records, the normal
build matches the tested bytes, and both shipped FPSP files remain unchanged.


Next retained improvement: native 040 projection division. The new-renderer 040
Project replacement uses extended round-to-zero FPU division for all but the
final point of an array, preserving the original final packed remainder registers.
It retains signed clipping/saturation and saves/restores FP0, FPCR, FPSR and FPIAR.
CUSTOM5 and original rendering retain the original routine; 060 is unchanged.

A read-only operand trace records 827,603 points from the prior baseline. Observer
invariance is established within each of two exactly matching startup-state pairs;
initial clock/cadence variation must not be mistaken for a code change. The final
same-build timing pair explicitly matches all three starting hunks except the
six-byte Project switch before accepting measurement. It improves 563 to 598
publications/2,000 PAL fields (+6.22%, 14.075 to 14.95 nominal fps). Its 250-field
prefix is 76 to 80 (15.2 to 16.0). The earlier committed build's 578/2,000 is a
separate historical result, not this feature's matched control. Both final paths
record zero FPSP entries and cache flushes. Hardware speed remains unmeasured.

Verification: 275 native original/replacement complete-array, GPR/CCR and FPU-state
comparisons, including recorded operands, clipping, quotient boundaries, signed
extremes and wrapping translations; an independent integer oracle and four
negative controls. A 400-update controlled flight produces seven identical full
64,000-byte displayed buffers and PNGs, with next-field DMA validation. Whole-game
end state is not bit-identical: clocks, the interrupt-updated audio period, and an
inactive sound-queue record differ. Both sound queues are empty and requested
periods agree; all other hunk bytes match apart from the intended patch. This is
not a new general state-equivalence waiver. CPU/option gates, normal/CHIP_ONLY
builds, unchanged FPSP files and all 246 inspected 060 FPU sites pass. Evidence,
limitations and reproduction tools remain in `tmp/dev/docs/optimization-20fps.md`.


Small retained scanline improvement: replace two MOVEQ/AND edge extractions in
new-renderer 040 ScanFillDown with register BFEXTU instructions, in the same code
space. No lookup tables, allocations or helper jumps are added. All 65,536
edge-word pairs pass native original/replacement GPR/CCR comparison and an
independent value/input oracle; four corruptions are rejected. Five complete
64,000-byte displayed-buffer/PNG comparisons pass, with next-field DMA checks.

The matched-start, same-build/emulator/seed extended pair improves 598 to 601
publications/2,000 PAL fields (+0.50%, 14.95 to 15.025 nominal fps); both short
prefixes remain 80/250 (16.0). An initial control and four pre-timing startup
mismatches are retained separately. Both accepted runs match a common recorded
startup state before timing; no selection was made using candidate frame counts.
This small emulator gain is not a hardware-speed claim. Enabled measurement has
zero FPSP entries/cache flushes. Normal/CHIP_ONLY builds, CPU/render-option gates,
unchanged FPSP binaries and original 060 edge/FPU instructions are verified.
The 20 fps hardware objective remains open.


Cache-balanced retained copy refinement: compare/write 8-byte units instead of
16-byte units. First-use initialization and two-buffer shadow invalidation are
unchanged. The shortened loop retains its old 90-byte footprint with unreachable
padding; every other slave code/data byte is identical to the prior build.

With exactly one same-address/same-length code write on BOTH sides, and identical
startup game hunks plus reported CPU registers, the 2,000-field pair improves
601 to 607 publications (+1.00%, 15.025 to 15.175 nominal fps). Its short prefix is
80 to 81 (16.0 to 16.2). CPU chip writes fall 3,110,105 to 2,139,708; these are
logical writes, not physical bus cycles. Both measured paths have zero FPSP
entries and cache flushes during the window; setup flushing occurs before it.

Verification: 80 full-buffer/history/guard/pointer cases, four checker negative
controls, five full displayed-plane/PNG comparisons through 57 controlled updates
with next-field DMA and shadow-coherence checks, CPU/render-option gates and
normal/CHIP_ONLY builds. FPSP files and all code outside the copy loop are unchanged.
Evidence: `balanced-eight-off/on`, `delta-eight-*` under `tmp/dev/tmp/opt20/`.
The earlier 4-byte candidate remains discarded; it passed native correctness but
its performance needs symmetric remeasurement before any hardware recommendation.
The edge margin is reconfirmed below; projection revalidation remains pending.
The hardware target remains unverified.


Pause checkpoint (2026-10-21): the corrected edge recheck uses the frozen
3fafdb93 build and exactly one same-address 12-byte write on each side. All three
starting game hunks (masking only the tested instructions) and reported CPU
registers match; slave/emulator/seed/executable hashes agree. It reconfirms
598 -> 601 publications/2,000 fields (+0.50%, 14.95 -> 15.025 nominal fps), with
80/250 on both short prefixes and zero measured FPSP entries/cache flushes.
Evidence: recheck-edge-off, recheck-edge-on-2 and recheck-edge-summary.json.
The first enabled startup was rejected before timing and remains preserved.

The corrected projection control records 563/2,000; its enabled attempt was
rejected before timing because two starting hunks differ. No corrected projection
speedup is claimed from this incomplete pair. Resume with that recheck before new
optimization. Earlier asymmetric comparisons retain the audit caveat above.

Work pauses at the user's request with production code at e0cd1fe7 and its
verified 8-byte-copy build intact. The best corrected extended result remains
607/2,000 (15.175 nominal fps), with 81/250 (16.2) in the short prefix. The 20 fps
objective is unfinished; Apollo hardware measurements remain postponed. Local
handoff, frozen builds and evidence remain under ignored tmp/dev/.


## 20 fps action plan (profile of e0cd1fe7, 2026-10-21)

This supersedes the four-step list under "Further optimization" above. Details,
tables and reproduction commands: `tmp/dev/docs/profile-20fps.md`.

Baseline: strict 040 NOMMU profile of the production build, action flight, fields
[2,2002): 608 publications (15.2 nominal fps), intervals 13 x 2, 406 x 3, 189 x 4
fields. Zero FPSP entries and no busy-wait: the game is entirely CPU-bound, so
the frame rate is 40 MHz divided by cycles per frame. 20 fps needs 800/2,000, i.e.
24.8% fewer cycles per frame (2.66 M emulated cycles -> 2.0 M).

Key finding: the emulator's 040 model charges a flat ~2.84 cycles for almost every
instruction, including FDIV, FMOVE, MULS.L, DIVS.L and memory bitfield operations.
Only MULS.W (20), DIVS.W (48) and chip RAM writes (~31) cost extra. The emulator
therefore measures instruction count, and it favours FPU-for-integer trades that
real 040 hardware does not reward. An approximate MC68040 re-weighting of the same
profile (`prof20_cost040.py`) is used alongside emulator A/B to rank candidates.

Hot spots (emulator % / estimated 040 %):

- ScanFillDown: 16.9 / 16.2
- _MaskSprite cookie-cut: 11.8 / 8.2
- Changed-block screen copy: 9.1 / 9.2
- DoRotPt0: 9.0 / 8.3
- Native projection: 5.8 / 11.5
- Polygon bounds/backface: 5.8 / 4.6
- MakeScanTable/GenLeft/GenRight: 5.9 / 5.0
- PlotColour: 3.0 / 3.0
- Cockpit and instrument images: 5.4 / 4.3
- Palette blend: 1.35 / 2.0

The scene has about 510 small polygons per frame (319 drawn, about 11 scanlines each), so per-polygon and per-scanline overhead dominates over pixel filling.

Rules for every step:

- One change at a time, gated to the new-renderer 040 path. CUSTOM5, original
  rendering and the 020/030/060 paths stay unchanged.
- Native original/replacement twin tests with guards, plus negative controls.
- Five or more complete displayed-buffer/PNG comparisons in controlled scenes.
- A balanced same-build 2,000-field A/B: exactly one same-address, same-length code write on each side, and matched startup hunks and registers.
- The estimated-040 delta from both profiles.
- CPU/option gates; normal/CHIP_ONLY builds with no relocations; FPSP files unchanged; 060 FPU sites unchanged.

Accept a change only if the estimated-040 cost falls. The emulator A/B must also not regress, except where step 1 explicitly attributes the difference to emulator FPU bias. Commit each accepted change.

0. Method and fixtures.
   - Freeze `tmp/prof20/current` as the baseline.
   - Add a second 2,000-field fixture. It uses the existing view tape, with external and cockpit views, so that changes do not overfit the cockpit flight.
   - Script `prof20_cost040.py` into every A/B report.
   - Prepare an Apollo calibration program for when the Amiga is available. It times DIVS.W, MULS.W/L, FDIV with FMOVE in/out, BFINS on memory, chip longword writes and fast-RAM CMPM streams, then replaces the model's constants.
   - Also record the hardware in-game FPS (CUSTOM4 bit 3) on the action flight.
1. Projection arithmetic.
   - Add an integer path for the 040 projection loop: the original DIVS.W/BVS per coordinate, the streamlined slave loop, and no FP save/restore.
   - Its outputs equal the FDIV path's, as already proven against the integer oracle, so reuse the 275 twin cases.
   - The emulator will report a loss (about 6%, from its DIVS.W 48 versus FDIV 2.8 charges). The 040 estimate is a gain of about 5% (2 x 27 versus about 2 x 50 cycles per point).
   - Keep both paths behind a switch. Default to integer once calibration confirms it, and record the decision.
2. _MaskSprite inner loop (`$4e53a`, from `$4e420`).
   - Restructure as row, then word, then plane.
   - Load and shift each mask word once and apply it to all 8 planes.
   - Move the first/last-word edge masks out of the inner loop (peeled edge words).
   - Make the read-modify-write longword-aligned.
   - Target about 8 instructions per word-plane, down from 19.
   - Expected gain: about 6% emulator, about 4% estimated 040.
   - Unlike the rejected sprite-on/sprite-zero trials, this removes per-plane mask work. Measure it on the 2,000-field window, not the 250-field window.
3. Cockpit-aware work avoidance. Measure first, then implement only the parts the data supports.
   - a) Trace one controlled flight and record:
     - the opaque/masked columns of the per-frame cockpit overlay (loaded code at game:$3816);
     - each _MaskSprite/_DrawSpriteImage/_DrawMonoImage call's rectangle and source;
     - the y and x range of every ScanFillDown span.
     Quantify 3D pixels drawn under fully opaque cockpit columns, and how often each instrument image changes.
   - b) If overdraw exceeds about 5% of raster work, clip 3D spans to per-scanline visible extents derived from the overlay's opaque columns. Output stays exact because those pixels are overwritten. Disable it when the overlay is not drawn, as in external views.
   - c) Skip comparing copy units known to hold unchanged opaque cockpit data in both the fast buffer and that chip buffer's shadow. Invalidate on overlay change and on PlayLevel.
   - d) Skip redrawing instrument images whose call arguments and underlying area are unchanged since the last frame, only if (a) shows it is safe.
   - Expected gain: 3-8% in total (unmeasured).
4. Scanline span setup.
   - About 24 instructions per scanline go into swap/BFEXTU/shift/sub before plotting.
   - Have GenLeft/GenRight, or a 320-entry left/right lookup, provide the word offset and edge masks directly.
   - Keep the colour-specialised narrow-span tables.
   - Expected gain: about 3% emulator, about 2% estimated 040.
5. Fused edge walking for convex polygons.
   - Replace three steps with stepping both edges in the fill loop, using the identical DDA arithmetic for exact edges:
     - MakeScanTable's vertex-list duplication;
     - the separate GenLeft/GenRight table passes;
     - the table re-read.
   - Keep the original path for any case the fused path does not cover.
   - Expected gain: about 4% on both measures. Highest effort.
6. Copy compare loop.
   - Unroll to one 32-byte cache line (four 8-byte units) per iteration with a single DBF, keeping the 8-byte granularity and the rewind logic.
   - Expected gain: about 2-2.5% emulator, less on hardware, where fast-RAM bandwidth bounds the loop.
7. Palette blend (`$249a`).
   - Skip the 256 x 3 blend when the factor and both source palettes are unchanged since the last call.
   - Otherwise replace DIVSL by 50 with an exact reciprocal multiply over the proven operand range.
   - Expected gain: about 1.3% emulator, about 2% estimated 040.
8. DoRotPt0 two-component delta case (`$59748`, 1,106 points per frame).
   - Measure how often a point's delta repeats the previous one within a shape. If common, reuse the three products.
   - Do not use FPU rotation: the emulator cannot evaluate it, and the expected hardware gain is small.
   - Expected gain: 0-4%, depending on the measurement.
9. Remaining tail, re-ranked after re-profiling: _DrawSpriteImage/_DrawMonoImage, slave line/plot, integer sqrt, ConeCheck/clipline, xTranslate (MULS.L, undercharged by the emulator).
10. Re-profile after every accepted step and update this budget.
    - The software target is at least 800/2,000 in the emulator, together with an estimated-040 cost of at most 2.0 M cycles per frame.
    - Then validate on the Apollo with calibrated constants: hardware FPS on both fixtures, and the frame-interval distribution.
    - Report the achieved hardware rate; do not equate it with the emulator figure.

Budget (estimated-040 savings, before interaction effects):

| Step | Saving |
|---|---:|
| 1 | 5 |
| 2 | 4 |
| 3 | 3-8 |
| 4 | 2 |
| 5 | 4 |
| 6 | 1-2 |
| 7 | 2 |
| 8 | 0-4 |
| 9 | 2 |
| **Total** | **23-33%** |

The emulator total without step 1 is about 24-31%. The goal is achievable only if steps 2-5 deliver close to their estimates. If they don't, report the shortfall rather than reducing detail or simulation work.

Step 0 done (method and fixtures):
- The baseline profile is frozen: 608/2,000.
- Same-build noise is ±1 publication, ±0.17% estimated-040 cycles per frame.
- Second fixture: the views tape (F2/F3/F5/F6, then back to F1).
  - It gives 464/2,000 (11.6 nominal fps).
  - In external views, cost shifts to the Gouraud/texture C2P path: c2p_32pixels_masked 13.3%, the three fills about 13%.
  - _MaskSprite is only 1.4% there.
- A/B reports now include estimated-040 cycles and an input-identity check.
- Balanced-profile pitfall: the harness's hunk image is unrelocated. Control bytes containing an absolute address must be rebuilt from the live base.
- An Apollo calibration program, calib040, is ready. It times the instructions the cost model depends on, plus the old and new mask loops. It has been checked functionally in the emulator. Hardware numbers are pending: the Amiga is not available.

Step 2 done (mask_sprite8_040):
- The 040 new-renderer patch list replaces _MaskSprite's eight-call plane loop at $4e400 (PL_P, 6 bytes; parameter block via PL_GA $4e518).
- Each mask word is loaded, edge-masked and shifted once, then applied to all eight planes.
- Each plane keeps the original longword read-modify-write order. Fully transparent words skip their no-op writes.
- Zero width or height falls back to the original eight one-plane calls.
- The routine leaves D0/D1/A0/A1, CCR, memory and the parameter block exactly as the original loop does. It returns through the game's epilogue at $4e42e.
- Original rendering, 030 and 060 keep the original bytes. CUSTOM5 does not affect this integer change.

Verification:
- **Native twins:** 192 cases pass. They run in the game process with _MaskSprite's real frame and cover:
  - all 16 shifts;
  - widths 1-40, heights 1-8;
  - edge masks, separate mask/data modulos, odd sources and plane strides.
- **Per-case checks:**
  - all 64,064 destination bytes are compared in the guest;
  - registers, CCR and the parameter block are compared;
  - an independent byte oracle checks all eight plane windows.
- **Negative controls:** four controls are rejected (a flipped byte, a wrong shift, wrong edge masks, a wrong plane stride).
- **Controlled scenes:** two 400-update pairs, cockpit and views, give seven identical complete displayed buffers and PNGs each.
  - Remaining end-state differences are the patch, the clocks, and one inactive audio-queue record (queue count 0).
  - The cockpit run also differs in one data-hunk byte (+$244): an interrupt-phase difference, since the faster run ends 101 fields earlier. It is not claimed as equal.
- **Gates and builds:**
  - The 040, 040 original, 040 CUSTOM5, 030 and 060 gates pass.
  - Normal and CHIP_ONLY builds have no relocations, and the normal build reproduces byte-identically.
  - FPSP files are unchanged.

Balanced 2,000-field pair:

| | Control | Candidate | Change |
|---|---:|---:|---:|
| Publications (nominal fps) | 606 (15.15) | 671 (16.78) | +10.7% |
| Emulator cycles/frame | | | -9.7% |
| Estimated 040 cycles/frame | | | -7.2% |
| Intervals (2/3/4 fields) | 12/398/195 | 50/583/37 | |

- Both runs use one same-address, same-length write and matched startup hunks and registers.
- The mask code itself saves about 100k estimated-040 cycles per frame. The rest of the drop is per-frame work changing with the faster cadence.
- Zero FPSP entries.
- One candidate start was rejected before timing (a one-vblank clock origin); the bounded retry was accepted.
- Hardware speed is unmeasured.
- Evidence: `tmp/dev/tmp/prof20/mask-*`, `mask-final-checks.json`.

Step 1 built behind a switch (project_int_040, CUSTOM1):
- New boolean `C1:B:68040 integer projection`. With CUSTOM1 set, the 040 new-renderer patch at $55e32 jumps to project_int_040 instead of project_fpu_040.
- project_int_040 is the same slave loop with the original DIVS.W/BVS per coordinate and no FPU save/restore. Outputs, registers and the final point's packed return values are identical.
- The default stays FPU (CUSTOM1 clear) until the Apollo calibration decides. CUSTOM5, original rendering, 030 and 060 keep the game's projection bytes either way.

Verification:
- **Native twins:** the 275 projection cases pass against the integer path, with full register and FP state. The independent integer oracle agrees, and four negative controls are rejected.
- **Controlled scenes:** cockpit and views pairs (CUSTOM1 clear/set), each with five identical complete displayed buffers and PNGs. The end states differ in the patch target, the clocks, and audio/interrupt-driven bytes at $4d72e-$4d850. Those come from the different emulated speed and are not claimed as equal.
- **Gates:**
  - 040 with CUSTOM1 jumps to project_int_040; without it, to project_fpu_040.
  - 040 original rendering, 040 CUSTOM5, 030 and 060 keep the original bytes.
- **Builds:** normal and CHIP_ONLY builds have no relocations; the normal build reproduces; FPSP files are unchanged.

Balanced 2,000-field pair (both boot CUSTOM1 clear; the candidate selects project_int_040 with one same-address, same-length JMP write):

| | FPU (default) | Integer (CUSTOM1) | Change |
|---|---:|---:|---:|
| Publications (nominal fps) | 671 (16.78) | 644 (16.10) | -4.0% |
| Emulator cycles/frame | 2,409,545 | 2,510,567 | +4.2% |
| Estimated 040 cycles/frame | 1,923,934 | 1,849,151 | -3.9% |

- As the plan predicted, the emulator loses (it charges DIVS.W 48 cycles, FDIV 2.8) and the 040 estimate gains (projection -236k, +139k per frame).
- The startup matched on the first attempt. Zero FPSP entries.
- Harness pitfall: the seed disk bakes the WHDLoad command line at enrolment. A run that reuses a seed boots with that seed's CUSTOM arguments, so a CUSTOM option cannot be A/B'd on a shared seed. Three earlier "integer" runs did this, silently ran the FPU path, and are discarded.
- Decision pending: run calib040 and both settings on the Apollo, then set the default and record it here.
- Evidence: `tmp/dev/tmp/prof20/intproj-*`, `intproj-ab.json`.

Step 3 measured and rejected (cockpit-aware work avoidance):

3a, measurement (cockpit probe, controlled flight):
- The panel image (game:$3816) is drawn after the 3D view and overwrites rows 97-145 almost entirely, with sloped edges. The 3D view stops at about row 145.
- 28.7% of ScanFillDown pixels, about 30% of its lines and 214 of 640 calls per frame lie entirely under opaque panel pixels.
- External views draw no panel.

3b, two implementations, both slower:
- Shared parts:
  - Each row's largest opaque panel run is derived by running the panel's own code over $00- and $ff-filled scratch frames.
  - The panel is predicted from last frame's view index and scroll, and the panel call verifies the prediction.
- Checks for both: identical displayed buffers and PNGs in the cockpit and views scenes, with 401 verified predictions and no misses. Native twins pass with negative controls (160 cases for the per-line version, 208 for the whole-call skip). The CPU/option gates pass.
- Per-line clipping: the clipped loop plots only the visible pieces of each line.
- Whole-call skip: a call is skipped only if every line lies inside its row's opaque run. Every other call runs the original code unchanged.

Balanced 2,000-field pairs:

| | Control | Per-line clip | Whole-call skip |
|---|---:|---:|---:|
| Publications | 671 | 650 (-3.1%) | 663 (-1.2%) |
| Emulator cycles/frame | 2,409,545 | +3.2% | +1.2% |
| Estimated 040 cycles/frame | 1,922,536 / 1,923,236 | +2.3% | +0.3% |

The control column shows the two control runs' estimated-040 values; each candidate's change is against its own control.

- **Why both lose:**
  - The game plots each line through an unrolled store table, so hidden pixels are cheap. The cost is per line and per call.
  - Per-line clipping adds about 204k estimated cycles per frame and saves 153k.
  - The fully hidden calls are small: skipping them saves 36k of the 376k fill cost (1.9% of the frame), against 49k for the test.
  - Even a much cheaper test would gain about 1% at most, and it would carry a one-frame risk whenever the panel changes after the first fill of a frame.
- **3c (copy units under the panel):**
  - Band 97-145 holds 1,960 of 8,000 copy units, but only about 300 change per frame.
  - The units that are provably unchanged still change 1-2 times per frame.
  - The ceiling is about 2% and needs complete write tracking. Not implemented.
- **3d (instrument redraw):** only about 40% of 2D image calls repeat their arguments (_MaskSprite 6 of 17). Not implemented.
- The slave is unchanged. Step 6 is next.

Harness pitfall: balanced-pair startup mismatches came from the boot's 1-4 vblank jitter. Only the vblank clock (_vblank_clock $4d884) and four copies differ. `CLOCK_NORMALIZE=1` writes the same fixed values on both sides before the entry comparison, which stays exact.

Evidence: `tmp/dev/tmp/step3/` (probe, `clip-ab.json`, `skip-ab.json`, the rejected sources and diff).

Step 6 done (copy compare loop, copy_changed_blocks):
- The compare loop handles one 32-byte cache line (four 8-byte units) per iteration with a single DBF.
- Each unit position has its own handler: a changed unit is written to the shadow and chip buffer, then the loop continues with the next unit. There is no rewind and no second pass.
- The destination is addressed relative to the source, so the loop no longer advances A0. A0 is set on return as before.
- Unchanged units cost about 4.25 instructions, down from 6; changed units cost the same as before.
- The 8-byte granularity and chip-write pattern are unchanged.
- The loop lives in a fixed 150-byte slot (`COPY_SLOT`), so an A/B swaps it with same-length writes.
- The delta copy exists only on the 040 new-renderer path (the shadow is allocated nowhere else), so CUSTOM5, original rendering, 030 and 060 are unaffected.

A first version is rejected. It rewound a line containing any change and redid it unit by unit, and it lost 2.5% estimated-040 cycles per frame (654 vs 671 publications). Changes cluster: about 31% of units but 55% of lines change per frame, so most lines paid for the rewind.

Verification:
- **Native twins:** the 80-frame copy test passes on two chip buffers, checking destination, shadow, pointers and guards. Its edits now also cover every longword of a 32-byte line, two units in one line, and the last longword. Four corruptions are rejected.
- **Controlled scenes:** cockpit (400 updates) and views pairs against the production loop give 7 and 5 identical complete displayed buffers and PNGs. The end states are identical apart from the clocks.
- **Gates and builds:**
  - The 040, 040 original, 040 CUSTOM5, 030 and 060 gates pass.
  - Normal and CHIP_ONLY builds have no relocations, and the normal build reproduces.
  - FPSP files are unchanged.

Balanced 2,000-field pair (the control runs the production 90-byte loop zero-padded to the slot):

| | Control | Candidate | Change |
|---|---:|---:|---:|
| Publications (nominal fps) | 671 (16.78) | 700 (17.50) | +4.3% |
| Emulator cycles/frame | 2,409,545 | 2,309,721 | -4.1% |
| Estimated 040 cycles/frame | 1,922,824 | 1,852,629 | -3.7% |
| Intervals (2/3/4 fields) | 44/594/32 | 107/584/8 | |

- The copy routine itself saves 32k estimated-040 cycles per frame (1.7%). The rest of the drop is per-frame work that changes with the faster cadence, mainly ScanFillDown and PlotColour.
- The startup matched on the first attempt, with the vblank clock normalized on both sides. Zero FPSP entries.
- Harness pitfall: monitor writes longer than about 90 bytes time out, so the tools split the 150-byte slot into equal chunks, the same calls on both sides.
- Hardware speed is unmeasured.
- Evidence: `tmp/dev/tmp/copy6/` (`copy-ab.json`, the scenes, twins, gates and the rejected version).

Step 7 done (palette blend, fade_cols_040):
- @AltFadeColsMiss ($249a) blends 256 RGB triples per call: per component,
  dest = (B + (A-B)*f/50) & $ff, skipping entries whose B is magenta ($ff,$00,$ff).
  Each component costs a MULS.L and a DIVSL.L.
- In flight there are two calls per palette change. $2ad0 passes f = 50, which is
  exactly a byte copy of A. $3244 then blends the result in place towards the palette
  at $b608 with a lighting factor of 2-48.
- The 040 new-renderer patch list jumps from $249a to fade_cols_040:
  - f = 50 copies the non-magenta entries byte by byte.
  - 0 <= f < 50 replaces the division with an exact reciprocal: |n|/50 = |n|*5243 >> 18
    for |n| <= 255*50, checked exhaustively for every factor and difference. One
    MULU.L replaces MULS.L + DIVSL.L.
  - Any other factor, and index ranges that would wrap the word index, run the
    original code.
- Reads and writes happen in the original byte order, so aliased destinations (the
  in-place call) behave identically. D0/D1, CCR (including X), the flag at $8020(a4),
  the stack frame and memory match the original.
- Like step 2, it is an integer change outside the CUSTOM5 block. Original rendering,
  030 and 060 keep the original bytes.

Why it is accepted by cycle count rather than by the frame A/B:
- For every call with count >= 1 and 0 <= f <= 50, the new code executes fewer
  instructions and no division, so it is faster under both the 040 table and the
  emulator's flat charge. Both in-flight call sites are in that class (256 entries
  from index 0).
- Only count 0, factors outside 0-50 and wrapping ranges cost about 10 cycles more
  per call (entry jump and range checks), and no in-flight call takes those paths.
- The first, copy-only version measured 699 vs 686 publications (est-040 +0.9%):
  - The routine itself saved 26k est-040 cycles per frame (1.4%).
  - The faster timing changed which frames the replay drew. The candidate had about
    4% more ScanFillDown calls per frame (850 vs 818) for the same polygon count, so
    the fill, copy and plot code all rose.
  - The frame total is dominated by this scene variation, which went the other way
    in step 6. The user accepted the change on its cycle-count guarantee.

Verification:
- **Native twins:** 216 cases pass, against a verbatim copy of the original routine
  on the same memory image. The guest compares the whole 4 KB region, the flag and
  the stack frame; the host compares D0-D7/A0-A6 and CCR.
  - The cases cover the copy path (58), the reciprocal path (78), fallback factors
    and wrapping index ranges (60) and empty calls (20).
  - They include magenta and partial-magenta entries, a skipped last entry, and six
    aliasing layouts.
  - An independent model of the original agrees.
  - Five negative controls are rejected: a wrong byte, a wrong register, a wrong X
    flag, a copy that ignores magenta, and an off-by-one quotient.
- **Controlled scenes:** cockpit (400 updates) and views pairs against the original
  routine give 7 and 5 identical complete displayed buffers and PNGs.
  - The end states differ only in the patch, the clocks, data-hunk byte +$244 (both
    scenes; step 2 saw it as an interrupt-phase difference) and hunk-0 $4d692-$4d693
    (cockpit).
  - These depend on the different emulated speed and are not claimed as equal.
- **Gates:** 040 and 040 CUSTOM5 jump to fade_cols_040; 040 original, 030 and 060
  keep $594f48e73f34.
- **Builds:** normal and CHIP_ONLY builds have no relocations, and the normal build
  reproduces. FPSP files are unchanged.
- Final balanced pair, for information:
  - Publications: 699 control vs 689 candidate. Est-040 per frame: +0.52%.
  - The palette code fell by 30.4k est-040 cycles per frame (1.6%): the original
    loop -35.8k, fade_cols_040 +5.4k. Emulator cycles fell by 24.4k.
  - The same divergence as the copy-only run (ScanFillDown +17k, copy +7k,
    PlotColour +5k) outweighs the saving in the frame total.
- Evidence: `tmp/dev/tmp/fade7/` (the copy-only run in `copy-only/`).

Step 8 done (DoRotPt0 delta table, rot_delta2_040):
- The handler at $59748 (about 1,100 two-component delta points per frame) adds
  M * (dx, dy) to the running sums A2-A4 with six MULS.W. The tail at $59778
  stores the point and dispatches the next command.
- Measurement (`tools/rotpt_probe.py`, cockpit and views scenes):
  - No point repeats the previous point's delta (0 of 2,024), so the planned reuse
    of the last products would never fire.
  - About 75% of points repeat a (delta, matrix) pair seen earlier in the frame. The
    same shapes (11 delta sequences) are drawn many times under few matrices (8).
- Implementation: the 040 new-renderer patch list jumps from $59748 to rot_delta2_040.
  - A 32 KB table (4 matrix slots x 256 buckets of 32 bytes) is allocated with the
    copy shadow.
  - The key compares the delta words and the matrix registers D4/D5/D6/A5 and the
    high word of D7 exactly.
  - A hit adds the stored three increments and loads the stored last product (the
    original's final D3). The sums agree modulo 2^32.
  - A miss multiplies as the original and fills the entry. A new matrix finds its
    slot or takes the oldest, which is invalidated with keys that hash to other
    buckets, so no key value is reserved.
  - Without the table, the handler multiplies.
  - D0/D1/D3, A2-A4, X and the stored points match the original. The miss and
    new-matrix paths use the stack below SP.
- Unlike step 7, this can be slower: a miss costs about 40 est-040 cycles more than
  the original, and break-even is about a 30% hit rate. In the action flight the hit
  rate is 84% (932 of 1,108 points per frame); the probes gave 68-70%.

Verification:
- **Native twins:** 220 command streams (2,043 points) pass against a verbatim copy
  of the original handler, which chains through the game's own tail.
  - The fixture owns dispatch entries 254 (chain) and 255 (return), so neither side
    runs the other's code.
  - The streams cover matrix-slot eviction (7 matrices for 4 slots), bucket
    collisions, (0,0), (32,0) and extreme deltas, matrices differing only in unused
    register halves, and the table-less path (190 points).
  - An independent model checks the points, D0/D1/D3 and the sums, and a cache
    model predicts 314 hits.
  - Four negative controls are rejected: a wrong sum, a wrong D3, a wrong X flag,
    and a stale entry from another matrix.
- **Controlled scenes:** cockpit (400 updates) and views pairs give 7 and 5 identical
  complete displayed buffers and PNGs. The end states are identical apart from the
  patch and the clocks.
- **Gates and builds:**
  - The 040 and 040 CUSTOM5 gates jump to rot_delta2_040 with the table allocated.
    The 040 original, 030 and 060 gates keep $4c9800032604.
  - Normal and CHIP_ONLY builds have no relocations, and the normal build reproduces.
  - FPSP files are unchanged.

Balanced 2,000-field pair:

| | Control | Candidate | Change |
|---|---:|---:|---:|
| Publications (nominal fps) | 689 (17.23) | 708 (17.70) | +2.8% |
| Emulator cycles/frame | 2,346,597 | 2,283,623 | -2.7% |
| Estimated 040 cycles/frame | 1,863,457 | 1,839,904 | -1.3% |
| Intervals (2/3/4 fields) | 77/600/11 | 127/577/3 | |

- DoRotPt0 falls by 125k est-040 cycles per frame and rot_delta2_040 adds 104k.
  The rest of the frame is nearly unchanged.
- The est-040 gain is smaller than the emulator's because the model charges the
  hit path's six memory-indirect table accesses at 5 cycles each.
- Zero FPSP entries.
- Possible refinement: address the entry through a saved address register instead
  of memory-indirect modes, and check the matrix once per object rather than per
  point.

Harness pitfalls:
- Dispatch entry 104 is not stable at run time. It pointed to $59788 in the twin
  boot, while the flight profile reaches $59748. Twins must own their chain opcode;
  a first run that chained through 104 ran another handler on both sides.
- This pair needed seven candidate starts: six failed on startup hunk differences
  that CLOCK_NORMALIZE does not cover (hunks 0 and 1), and the seventh matched exactly.
- Evidence: `tmp/dev/tmp/rot8/` (probes, twins, scenes, gates, `rot-ab.json`).

Step 4 done (scanline span setup, sfd_span_040):
- ScanFillDown's loop at $6c520 (about 4,000 lines per frame) took each line's
  edge integer parts through BFEXTU, shifts and subtractions, then dispatched on the
  span's long count. Spans crossing a long boundary (about 680 per frame) wrote each
  of the eight planes with two BFINS on memory.
- Implementation: the 040 new-renderer patch list jumps from $6c514 (after the
  entry has computed A0 and the colour word) to sfd_span_040.
  - Per-x tables in the slave give the long offset and both edge masks (x 0-319,
    3,200 bytes, generated at assembly time).
  - A span inside one long, and each edge long of a wider span, is plotted by the
    game's colour-specialised routine (PlotColour $6a4b8). The longs between the
    edges are filled plane by plane, as the original does.
  - A non-empty line whose right edge lies beyond x = 319 continues in the original
    loop from that line. None did in the flight.
  - Memory, D0, D7, A0, A2-A5 and the flags at exit equal the original's. D1-D6, A1
    and A6 hold other scratch values. The only caller ($5f1c4, from the edge walker)
    restores A6 and A1; the edge walker and Polygon write the others before reading
    them. A build that loads fixed junk into those registers at exit gives the same
    displayed buffers in both scenes.
- Cost (est-040): about 14 cycles fewer per line inside one long and about 150 fewer
  per wider line, but about 22 more per call (entry and exit). A one-line call inside
  one long is about 8 cycles slower than the original; calls average about 4.6 lines.
  So this step is accepted on the frame pair, not on a cycle-count argument.

Verification:
- **Native twins** (`tools/opt20_sfd_test.py`): 187 calls (6,670 lines) pass against
  the original loop, which the fixture selects by rewriting $6c514 per side.
  - Lines: 341 empty or crossing, 1,133 inside one long, 853 with adjacent edge longs,
    3,401 with longs between the edges, 644 aligned left edges, 847 aligned right
    edges and 500 beyond x = 319. Eight calls draw no line.
  - The guest compares the whole 80 KB buffer; the host compares D0, D7, A0, A2-A5,
    SP and CCR, and checks the candidate's rows against an independent model.
  - Four negative controls are rejected: a wrong bitplane byte, a wrong kept register,
    a wrong X flag, and a model whose right edge is exclusive.
- **Controlled scenes:** cockpit (400 updates) and views pairs give 7 and 5 identical
  complete displayed buffers and PNGs. End state differs only in timing-dependent
  game bytes (cockpit $4d692-$4d693; views $40cb7, $4d72e-$4d72f, $4d77d), besides
  the patch and the clocks. The scratch-register poison build matches the candidate's
  images; its end state differs only at patch sites holding slave addresses and $40cb7.
- **Gates and builds:**
  - The 040 and 040 CUSTOM5 gates jump to sfd_span_040. The 040 original, 030 and 060
    gates keep $4dfa000ad1fc.
  - Normal and CHIP_ONLY builds have no relocations, and the normal build reproduces.
  - FPSP files are unchanged.

Balanced 2,000-field pair (matched on the first candidate start):

| | Control | Candidate | Change |
|---|---:|---:|---:|
| Publications (nominal fps) | 708 (17.70) | 746 (18.65) | +5.4% |
| Emulator cycles/frame | 2,283,623 | 2,167,299 | -5.1% |
| Estimated 040 cycles/frame | 1,840,235 | 1,687,993 | -8.3% |
| Intervals (2/3/4 fields) | 126/578/4 | 240/504/1 | |

- ScanFillDown falls by 307k est-040 cycles per frame; sfd_span_040 adds 157k and
  PlotColour 20k (it now also plots wide spans' edges). Span drawing went from 374k
  to 245k.
- The gain is above the plan's 2% because the wide spans' BFINS pairs (about 100k
  est-040 cycles) went too.
- The estimate is now below the 2.0 M cycles/frame software target; the emulator is
  at 746 of the 800 publications.
- Zero FPSP entries.

Harness pitfall: the first poison build loaded the junk before restoring A5 from
D5, which crashed the game (illegal instruction after a jump to $5A). Poison only
after the kept registers are restored. Poison scenes need DELTA_LISTING set to the
poison build's own listing.

Evidence: `tmp/dev/tmp/sfd4/` (twins, gates, scenes, poison scenes, `sfd-ab.json`).

Step 5 measured and rejected (fused edge walking, poly_fill_040):
- Polygon ($60d92 onwards, about 320 drawn polygons per frame) doubles its vertex list,
  builds left and right edge tables (GenLeft $5f252, GenRight $5f1e0), and walks them
  ($5f124) with one ScanFillDown call per run of lines between vertices (about 820
  calls per frame).
- Implementation tried: the 040 new-renderer patch list jumped from $60d92 to
  poly_fill_040.
  - Both edge lists were built with GenLeft's and GenRight's arithmetic into slave
    records, stepping round the vertex list instead of a doubled copy.
  - The walker's runs and its bottom line were drawn in one pass with sfd_span_040's
    line body, shared as a macro (sfd_span_040's code stayed byte-identical).
  - A climbing chain drew nothing, as in the original.
  - These inputs ran the original code: more than 17 vertices, a chain that does not
    reach the bottom within one lap, chains ending on different rows, and rows outside
    0-199.
  - The vertex limit matters: the game's edge tables hold 17 records (16 edges and
    the end) per chain. A longer left chain runs into the right table, and a longer
    right chain runs into the reciprocal table at $62e70. A chain has at most n-1
    edges.
- Verification passed:
  - Native twins: 194 cases (7,368 lines) against the original Polygon tail with the
    game's own ScanFillDown loop. They cover 1-32 vertices in both windings, a
    16-edge chain, x beyond 319, climbing chains and every fallback, with an
    independent model of the doubled list, GenLeft/GenRight and the walker.
  - Controlled scenes: cockpit and views pairs gave identical displayed buffers.
  - A poison build passed both scenes. It loaded junk into the exit registers and
    flags, and into exactly the bytes the original writes but poly_fill_040 does not
    (the edge records' bytes 0-9 and end records' bytes 0-3, the doubled list,
    ScanFillDown's return cell).
  - The 040, 040 original, 040 CUSTOM5, 030 and 060 gates passed.
  - Normal and CHIP_ONLY builds had no relocations, and the normal build reproduced.

Balanced 2,000-field pair (after one round of run-overhead tuning; the first version
gave the same publications and est-040 -0.54%):

| | Control | Candidate | Change |
|---|---:|---:|---:|
| Publications | 746 | 743 | -0.4% |
| Emulator cycles/frame | 2,167,299 | 2,176,050 | +0.4% |
| Estimated 040 cycles/frame | 1,687,608 | 1,682,124 | -0.33% |

- The emulator measure regresses, so the step is rejected. The slave is unchanged.
- Why the plan's 4% did not materialise, from instruction counts per frame:
  - The original's work outside the line loop is about 71k instructions per frame:
    GenLeft/GenRight and the walker 48k, the Polygon tail including the doubling
    9.5k, and the ScanFillDown and sfd_span_040 entries and exits about 13k.
  - poly_fill_040 still spent about 63k instructions per frame there:
    - edge building 33k, the same arithmetic as GenLeft/GenRight;
    - per-polygon checks and setup 13k;
    - run changes 17k.
  - So only about 8k instructions per frame (under 1%) were saved, within the scene
    variation of a frame pair. The per-call overhead the estimate assumed is small
    after step 4.
- A worthwhile remaining gain would have to come from the line body itself (about 24
  instructions per line, 4,100 lines per frame) or from fewer edges.
- Harness pitfall: the Gouraud and texture fills read stale words of their own edge
  end records (fractions at offsets 12-13 and 20-21). These are bytes neither Polygon
  version writes. A poison that fills whole tables therefore changes the views images
  without showing a real dependency. Poison only the bytes the original writes.
- Evidence: `tmp/dev/tmp/poly5/` (`poly-rejected.s`, `poly-rejected.diff`, twins,
  gates, scenes, poison scenes, `poly-ab.json`, the first run in `first-run/`).

Step 9 done (re-ranked tail; integer square root, isqrt_040):
- Re-profile of production (a9b21fbb, the step 5 control): 746/2,000 publications,
  emulator 2.17 M and estimated 040 1.69 M cycles per frame. Tail ranked by est-040
  cycles per frame:

| Routine | Est-040 | Ceiling of a rewrite |
|---|---:|---|
| xTranslate ($5fff4) | 54.7k | none: 48.7k is nine 64-bit MULS.L |
| _DrawSpriteImage ($4f54e) | 26.0k | about 6k: the byte loop is 19.7k |
| slave draw_line_new + plot | 42.5k | about 3-7k: per-pixel JSR and address setup |
| _DrawMonoImage ($4e6b4) | 20.2k | about 5k |
| @SquareRoot ($4bdca) + distance caller | 14.3k + 4.4k | measured below |
| ConeCheck ($60b7c) | 13.5k | about 3k: two DIVS.W on some calls |
| clipline ($5f86c) | 9.6k | small: compare/branch chains |

- xTranslate sums the high longs of nine 32x32->64 products. An FPU version needs a
  separate floor per product (fmul plus a conversion under round-to-minus), which costs
  about the same as MULS.L under the 040 table, adds FPCR and register saves, and loses
  in the emulator. Not implemented.
- The other items are under 0.4% each and were not implemented. The unnamed hot code
  next in the list (the generated cockpit-overlay blitter, the terrain grid loop at
  $38236) is already tight.
- Implemented: @SquareRoot returns floor(sqrt(D0)) with 16 fixed bit-by-bit iterations.
  While the bit exceeds D0 and the root is zero an iteration changes nothing but the
  bit, so isqrt_040 finds the highest power of 4 <= D0 with BFFFO and jumps into the
  same iterations, unrolled with constant bits. D1-D7/A0-A6 and CCR (X/V/C clear, N/Z
  from the root) match the original; only dead stack below SP differs.
- Accepted by cycle count: on every input it executes fewer instructions (at most 122
  against at least 135) and fewer est-040 cycles (at most about 172 against at least
  about 215).

Verification:
- **Native twins:** 4,922 inputs pass against a verbatim copy of the original, with
  junk in D1-D7/A0-A6 and X set and clear. They hit all 17 entry blocks (every
  leading-bit position, 0 and 2^32-1), squares and their neighbours, powers of two
  and four and their neighbours, and pseudo-random values of every magnitude. An
  independent model (floor(sqrt), kept registers, CCR) agrees. Five negative controls
  are rejected: a wrong root, a wrong register, a wrong X or Z flag, and an off-by-one
  root on both sides.
- **Controlled scenes:** cockpit and views pairs against the original routine give
  identical displayed buffers and PNGs.
- **Gates:** 040 and 040 CUSTOM5 jump to isqrt_040; 040 original, 030 and 060 keep
  $48e70f002e00.
- **Builds:** normal and CHIP_ONLY builds have no relocations, and the normal build
  reproduces. FPSP files are unchanged.

Balanced 2,000-field pair, for information:

| | Control | Candidate | Change |
|---|---:|---:|---:|
| Publications | 746 | 731 | -2.0% |
| Emulator cycles/frame | 2,167,299 | 2,211,772 | +2.1% |
| Estimated 040 cycles/frame | 1,687,676 | 1,717,002 | +1.7% |

- The square root fell by 14.1k est-040 cycles per frame and isqrt_040 costs 9.3k:
  net -4.8k est-040 (-0.29%) and -8.5k emulator cycles (-0.39%).
- As in step 7, the faster timing changed which frames the replay drew: about 4% more
  ScanFillDown calls per frame (846 vs 816), so the fill, copy and plot code rose
  (+8.8k, +8.5k, +5.5k est-040). The frame total is dominated by this divergence.
- The 20 fps action plan's code steps are now complete or rejected. What remains is
  step 1's default and the Apollo validation of step 10, both waiting for hardware.
- Evidence: `tmp/dev/tmp/sqrt9/` (twins, gates, scenes, `sqrt-ab.json`).
