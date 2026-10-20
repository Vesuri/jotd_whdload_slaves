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

### 8. Undo the chip-RAM merge

- From the `TFX.040` hunk layout and step 6 symbols, list what truly needs chip RAM
  (bitplanes, sprites, copper lists, blitter sources, audio).
- Load the merged data/BSS into fast RAM, place the chip-only objects in a chip
  allocation and relocate references to them (as `reloc_2_0_020` does for `TFX`).
  Replace the `AllocMem` chip override for the new path.
- Exit: identical screenshots in the fixed window; fps measured.

### 9. Remove FPU traps from the hot path

- Generate patches for all `FINTRZ` and `FMOVECR` sites from disassembly rather than
  traces; check every constant used.
- Replace the transcendental sites (or the library wrappers they sit in) with 040-native
  routines of the precision the game needs; compare against FPSP results over the
  inputs seen in play.
- Keep FPSP installed as the safety net.
- Exit: zero FPSP entries during the fixed window; identical state at the window's end,
  or differences explained; fps measured.

### 10. Port paraj's rendering to `tfx.020`

- Fills (`@GouraudFill`, `_TextureFill`, `ScanFillDown`), fast-RAM render buffer and
  chunky-to-planar, `start_frame`, then the uncapped and 1-frame options.
- Exit: per-routine equivalence checks, frame screenshots equal to the original
  rendering, fps measured.

### 11. 68040-specific tuning

- With SMC fixed, drop the per-frame cache flushes that are no longer needed; run fast
  RAM in copyback.
- `MOVE16` for line-aligned copies to chip, 040 scheduling of the hottest loops,
  FPU values kept in registers.
- Exit: each change A/B-measured; keep only measurable wins.

### 12. Palette glitches

- Reported symptom: a stray yellow colour on the A1200/040 (details not remembered).
  Reproduce on A1200/040 and compare with A1200/020: screenshot menus, briefing,
  cockpit, external views and fades; search frames for unexpected yellow entries in
  the palette or copper list.
- Suspects: `_SetPal`/`_DiffSetPal` writing colour registers outside vertical blank (a
  race that a faster CPU exposes), debug palettes or overrides (`_davespal`,
  `_greenpal`, `_colour_override`), bugs 30/67, fade routines.
- Exit: root cause written down, fix verified with screenshots on both machines.

### 13. Selection, options and regression

- Auto-select `tfx.020` with the new path on 040 + FPU. Leave 020/030/060 selection and
  behaviour unchanged unless measured better; gate new patches by CPU and options.
- Exit: every executable and option boots on 020, 030, 040, 060 configurations.

### 14. Real hardware and release

- User runs the build on the A1200/040. Update the ReadMe. Commit one coherent feature
  per commit under the fork rules, then open the pull request.

## Open questions

- Where the yellow colour appears; step 12 searches for it.
