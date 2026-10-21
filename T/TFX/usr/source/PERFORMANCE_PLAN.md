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
Revalidation of the earlier retained edge/projection margins is still pending.
The hardware target remains unverified.
