# Road Rash: race trace analysis and plan for smooth play on faster CPUs

Status: A1–A5 and B1–B5 complete (2026-10-20); C1–C3 complete (2026-10-21);
D–G remain open. Accepted A evidence
and limitations are in §9; B results and the 25 fps safety limit are in §10. Sections 1–6 retain the original exploratory measurements;
they are not the fixed-field A baseline. Slave baseline: shipped v2.0
(`RoadRash.slave`, SHA-256 `9d2f2302…a563`), identical to this source except for the date
string and two `PL_STR` lengths, which differ because the shipped slave was built with older
WHDLoad macros. All addresses are absolute: the game is loaded at `$80000` in chip BaseMem,
so slave patch offsets are the address minus `$80000`.

## 1. Summary

- **Gameplay speed is independent of the frame rate.** The race uses a variable time step:
  each frame advances the simulation by the number of fields the previous frame took, and the
  race clock and steering run per field in the interrupt. Measured on six CPU
  configurations from 9.2 to 24.1 fps, the distance covered in 490 race fields of full
  throttle agrees within 0.7% (§4). A faster CPU therefore gives smoother play, not faster
  play. Untested: 50 fps (delta 1), which no machine reaches today.
- **Frame rates today** (race, full throttle, Sierra Nevada level 1): 68000 A500 9.2 fps;
  68020 A1200 12.5 fps with or without fast RAM; 68020 with WHDLoad `Cache` 16.7 fps;
  68030/50 with `Cache` 16.8 fps; 68040/25 23.5 fps; 68060/50 24.1 fps. On 040/060, frames
  alternate between 2 and 3 fields, which judders. A 060/50 is barely faster than a 040/25:
  above the 020, the game is bound by chip RAM and the blitter, not by the CPU.
- **Why:** all game code, data, stack and graphics live in chip RAM (BaseMem `$0-$fffff`).
  The slave enables no CPU caches, and blitter priority (`BLTPRI`) is on. The CPU therefore
  makes no progress during any of the 142 blits per frame (18.8% of the 68020's time), and
  every uncached instruction fetch competes with DMA.
- **Where the time goes** (68020/14 uncached, 4 fields per frame): renderer 48.9% (road
  rasteriser 21.7%, background clear 8.9%, objects 13.4%), game logic 29.7% (road geometry
  13.3%), frame-end wait 9.6%, HUD 6.2%, copper/sprite rebuild and sprite patches 4.0%,
  interrupts about 3.5% (included in the above).
- **Plan outline:** a measurement harness (A) and correctness fixes (B) come first. Then
  consistent simulation with uncapped vsynced rendering (C), caches and `BLTPRI` (D),
  blitter work and overlap (E), then CPU work in fast RAM (F), then release (G).
  Throughput targets: at least 25 fps on 030/50, 040 and 060;
  at least 16.7 fps on a 68020 with fast RAM; no regression on the A500. 50 fps on the 060 is
  a stretch goal that needs E and F.

## 2. Method and reproducibility

The harness is the ignored `tmp/dev` of this worktree (AmigaXDev shared environment):

| Tool | Does |
|---|---|
| `tools/build-fsuae.sh` | private native FS-UAE: AmigaXDev patches plus `monitor input` (joystick events `JOY2_*`; `JOY1_*` is the mouse port) |
| `tools/drive.py OUT race` | route (fire on the intro, high-score table and "press fire to race" screens), then a 500-field Barto trace (5 × 100) with `JOY2_UP` held, reduced with `amigaxdev.callprofile` |
| `tools/rate.py OUT` | machine-independent route (`to_race`: fire until the race hook `$a5916=$87040` runs), then 250 samples of 2 fields: frames from the per-frame record rotation `$a726e`, delta `$a6f00`, race field counter `$a5d4c`, player track position `$a5d64` |
| `tools/matrix.sh` | `rate.py` across the machine cells in §3 |
| `tools/functable.py`, `tools/summary.py` | per-function self/inclusive table from the reduction |

Trace: `a1200-fast` (68EC020/14, 2 MB chip, 8 MB fast), `WARP=1 DETERMINISTIC=1`, race
fields 3300–3800 from boot, 125 frames, 284,204 CPU cycles per field. `monitor fields N`
runs N+1 fields when the emulator is already stopped at a vsync, which it always is in
these tools. The harness accounts for that. Under the native stub, `monitor fields` never
returns with the `a1200-030` preset's MMU, so the 030, 040 and 060 cells run cycle-exact
without an MMU.

## 3. Machine matrix (baseline)

500 fields of full throttle from the start line. "Distance" is the change in the player's
track position (`$a5d60+4`) over the first 490 race fields of the window.

| Cell | CPU / memory | fps | Fields per frame (samples) | Distance @490 |
|---|---|---:|---|---:|
| `a500-1m` | 68000/7, 1 MB chip + 1.5 MB slow | 9.2 | 5: 130, 6: 120 | 3,363,656 |
| `a1200` | 68EC020/14, 2 MB chip | 12.5 | 4: 250 | 3,364,352 |
| `a1200-fast` | + 8 MB fast | 12.5 | 4: 250 | 3,364,352 |
| `a1200-fast+cache` | + WHDLoad `Cache` | 16.7 | 3: 250 | 3,370,797 |
| `030-50` | 68030/50 cycle-exact, no MMU | – | WHDLoad stopped on "Illegal Instruction ($10) at $68" in the front end (one run) | – |
| `030-50+cache` | + `Cache` | 16.8 | 2: 5, 3: 245 | 3,387,906 |
| `040-25` | 68040/25 NOMMU | 23.5 | 2: 208, 3: 42 | 3,377,760 |
| `040-25+cache` | + `Cache` | 23.5 | identical | 3,377,760 |
| `060-50` | 68060/50 NOMMU | 24.1 | 2: 224, 3: 26 | 3,365,688 |
| `060-50+cache` | + `Cache` | 24.1 | identical | 3,365,688 |

The `Cache` option changes nothing on 040/060 without an MMU. Whether the caches are on or
off there was not measured (item A3b). The 1 MB chip A500 is the smallest machine that
fits: BaseMem is `$100000` and must be chip RAM.

## 4. Game-time model (frame rate versus gameplay speed)

**Answer: gameplay advances at the same speed on every CPU. Faster CPUs render more
frames of the same motion.**

Mechanism (verified from the code and the trace counts):
- **Per-field tick.** The copper list raises a SOFT interrupt (level 1) once per field at
  line `$fa`, below the display. Handler `$aea2c` acknowledges it, increments `$aec0c`
  (fields since the last swap) and `$aec0d` (free-running; never read), reads the
  controllers, then calls `$aeed6`. `$aeed6` runs the palette fader `$aee2a` and the sound
  effect sequencer `$b5c5e`, then `jsr ($a5916)`: the game's per-field hook, `$87040`
  during a race (installed at `$a8c4c`).
- **Hook `$87040` (per field).** It does `$a6efe += 1` (fields since the last accepted
  frame) and runs the race clock `$86fe0`: `$a5d4c` counts total race fields, `$a5d58`
  counts to 60, then a BCD second is added. It also runs steering and throttle `$87298`
  from the latched joystick, so control response is per field.
- **Frame handshake.** The main loop ends each frame at `$871dc`: it sets a ready flag
  (`$a7238`/`$a723a` via `$a7266`) and rotates the per-frame record pointer `$a726e`. At the
  next field the hook sees the flag, flips the consumer side (`$8713a`) and latches the
  delta at `$86f98`: `$a6f00 = $a6efe` (forced ≥ 1), then clears `$a6efe`.
- **Delta use.** `$a6f00` is read at about 40 sites in the simulation: speed +=
  acceleration × delta (`$8b4be muls`), distance step = speed × delta (`$8b4dc mulu`),
  animation timers (`$8d318`), race timers (`$874a4`), the event countdown (`$90a28`),
  `$8ef66 divs`, and more.
- **No cap.** The race loop's swap `$aecba` only waits for the next SOFT tick, so the race
  can reach 50 fps. The 2-field minimum `$aeca8` is used only in the attract/intro. The
  swap writes the plane pointers into the copper list during the blank lines after line
  `$fa`, so it cannot tear at any speed.

Evidence that gameplay speed is frame-rate independent: §3, distance at 490 race fields is
3.36–3.39 M at 9.2, 12.5, 16.7, 16.8, 23.5 and 24.1 fps (spread 0.7%).

Caveats:
- **NTSC heritage.** The clock counts 60 fields per second, so on PAL the race clock and
  (presumably) the whole game run at 5/6 of NTSC speed: 27 clock seconds in 32.3 s. This is
  independent of the CPU and is not part of this plan.
- **One frame-tied effect.** `$89d32` advances `$a5990` once per frame (mod 8). `$8a2a4` uses
  it to pick one of four animated roadside sprite frames (`$ac..$af`), so that animation runs
  faster at higher frame rates. Cosmetic (item B3).
- **Untested deltas.** Delta 1 (50 fps) is untested, and large deltas have no upper clamp
  (item B4).
- **Judder.** Frame N moves by the duration of frame N−1. When frames alternate between 2
  and 3 fields (040/060 today), each motion step is one frame out of phase with the display,
  which can judder (C now addresses the simulation/presentation dependency).
- **Unexplained path.** The paced path `$8aff0` (hook, fed at `$87722`) and the main-loop
  gate `$875bc` were not exercised in the window (item B5).

## 5. Program structure

### Memory and display
- **BaseMem `$0-$fffff` is chip RAM.** The game is at `$80000-$b6000`, with data cells
  interleaved in the code and variables at `$a59xx-$a8xxx` and `$aec0c-$aec0e`. The trace
  found no self-modifying code: every byte that changes in the code area is a data word
  after an `rts`.
- **Screen buffers.** Two buffers of 4 non-interleaved planes, at `$6f780` and `$77cc0`.
  Planes are `$20d0` apart, with 42-byte lines in the blits. `$404` is the front buffer and
  `$408` the back.
- **Copper list at `$147e`.** A single list built from chained `COP1LCL`/`COPJMP1` jumps:
  `BPLCON0=$4000` (4 planes, 16 colours), plane pointers (written by the swap `$aec2c`),
  palette, a sky gradient on `COLOR00` every 2 lines (`$32-$58`), sprite-multiplex
  sub-lists at lines `$31/$43/$51/$64`, per-line `COLOR03` at `$d1-$ec`, then at `$fa` planes
  off and the SOFT interrupt. `$b076e` rebuilds the sky/horizon and sprite sections after
  each swap.
- **DMA.** `DMACONR` reads `$07f7` in the race, so `BLTPRI` is on. Slot shares per field:
  free 28.0%, CPU 32.1%, bitplane 22.5%, blitter 13.2%, refresh 1.8%, copper 0.9%,
  audio 0.8%, sprite 0.7%.

### Interrupts (constant per field, about 10k cycles = 3.5% of a 68020 field)

| Vector | Handler | Use | Cycles per field |
|---|---|---|---:|
| L1 `$64` | `$aea2c` | SOFT from the copper: tick, controllers, fader, sound effects, game hook | ~4,000 (incl. hook `$87040`) |
| L2 `$68` | `$ae9b8` | keyboard; the slave's `kbint` at `$ae9d8` (Help quits) | 0 in the window |
| L3 `$6c` | `$a88f2` | unused (clears `INTREQ`); `$aead6` is a blitter-done handler with a job ring at `$aeb84`, never installed in the race | 0 |
| L4 `$70` | `$b5ad4` | audio channel end | ~50 |
| L6 `$78` | `$b527e` | CIA-B timer B, 50.3 Hz: music player `$b537e`/`$b5498` | ~5,900 |

### Race frame pipeline (main loop `$8747e`, once per frame)

1. Timers, `$89a38` speed digits, `$90a10` event countdown.
2. Simulation (when racing): player control/physics `$8b486`, actor updates, AI `$8d2c0`,
   collisions `$8c130`/`$8c5a8`, ranks `$892a0`, nearest opponent `$901ae`.
3. `$89138` camera offset; gate `$875bc` (skip the frame if the hook has not consumed the
   previous one).
4. Road geometry: projection `$8970e` → 4 edge rasterisations `$89a9c` → per-line widths
   `$89656`.
5. Objects: `$8a5d0`/`$8a3be`/`$89d20` build the draw list (`$a7c3e`, 20-byte entries);
   `$8b02e` projects and clips; `$8b37e` depth sort.
6. `$8eff8` sound triggers; `$89048` road stripe line list.
7. HUD `$88610` (mirrors, speed, tacho, clock, position) and `$88cea` (damage bars → dials
   `$b0c8a`).
8. `$b0db4` rider sprite patches; render `$afd60`; wait and swap `$aecba`; `$b2b2c`;
   copper/sprite rebuild `$b076e`; frame done `$871dc`.

## 6. Where the time goes (68020/14 uncached, 125 frames)

Percent of all traced CPU cycles; "incl" is inclusive. Interrupt cycles are counted inside
whatever they interrupted.

| Group | incl% | Main contributors |
|---|---:|---|
| Renderer `$afd60` | 48.87 | road `$b10d0` 21.65, objects `$afdce` 13.37, background `$b1744` 8.86, parallax `$b2b82` 3.24, mask pass `$b16d6` 2.24 |
| Game logic | ~29.7 | road geometry 13.3 (`$89a9c` 5.14, `$89656` 3.84, `$8970e` 2.72, `$89048` 1.61), draw list 5.6, physics `$8b486` 3.48, collisions 3.2, AI `$8d2c0` 2.91 |
| Frame-end wait `$aecea` | 9.60 | spins until the next SOFT tick |
| HUD `$88610` + `$88cea` | 6.21 | mirrors, digits, needles, dials |
| After-swap `$b076e`, sprite patches `$b0db4` | 3.96 | copper sky/sprite rebuild, rider colour patches |

Blitter stalls (CPU cycles while a blit runs, included in the groups above): **18.82%**.
That is 214k CPU cycles, about 0.75 field per frame. Breakdown: background clear 8.30, bobs
6.95, hills 1.44, dials 1.15, mountains 0.64, needle restore 0.33. Every wait is
`btst #6,2(aN)` twice, then `bne`. The `bne` never loops: the first chip access after
`BLTSIZE` absorbs the whole blit, which is the effect of `BLTPRI`.

### Functions (≥ 0.4% inclusive or self)

| Address | incl% | self% | Calls per frame | Purpose |
|---|---:|---:|---:|---|
| `$8747e` | 99.19 | 0.27 | 1 | race main loop |
| `$afd60` | 48.87 | 0.03 | 1 | render driver |
| `$b10d0` | 21.65 | 14.03 | 1 | road rasteriser, CPU, per scanline (≈81 lines) into planes 0/1, unrolled `move.l` span tables; 6.5 KB of chip stores per frame |
| `$b1994` | 7.21 | 6.99 | 131 | road edge-word composer (4 plane words from per-stripe flags); `movem` and duplicated loads |
| `$afdce` / `$afe12` | 13.37 / 13.06 | 0.35 / 2.69 | 1 / 15.9 | object walk, far to near; dispatcher: LOD `divu #$49`, ~40-compare type cascade, clip, call bob |
| `$b3ba2` (+`$b3c6e`) | 10.29 | 0.73 (+9.30) | 18.2 | masked bob: 2 blits rebuild the mask (`$0ffe`, `$0bfa`), then 4 cookie-cut blits `$0fca`; ≈105 blits per frame |
| `$aecba` / `$aecea` | 10.22 / 10.17 | 0.01 / 9.60 | 1 | wait for the next tick, swap `$404`/`$408`, write copper plane pointers |
| `$b1744` | 8.86 | 8.46 | 1 | background: 6 blits clearing planes above the horizon (`$0900`) and filling planes 2/3 below (`$09ff`); 8.30% of it is stall |
| `$89a9c` / `$89ac8` | 5.14 / 3.02 | 2.05 / 2.97 | 4 / 68 | road edge rasteriser (DDA with reciprocal table `$89b1e`), four edges |
| `$88610` | 4.72 | 0.04 | 1 | HUD redraw each frame (mirror clears `$88970` ≈4500 words, digits, tacho) |
| `$89656` | 3.84 | 3.43 | 1 | per-scanline road half-width/centre clamp and stripe shift |
| `$8b486` | 3.48 | 0.66 | 1 | actor motion: speed += accel × delta, step = speed × delta, steering, crashes |
| `$b2b82` | 3.24 | 0.02 | 1 | parallax: mountains `$b2c0c`/`$b2d36` (4 shifted copies), hills `$b2b94`/`$b2ea4` (copy + cut-out `$0f02`) |
| `$8d2c0` / `$8d40a` | 2.91 / 1.94 | 0.51 / 0.25 | 1 / 5.3 | AI per actor (behaviour table `$9422a`), lane choice `$8d940`/`$8d966` |
| `$8970e` | 2.72 | 2.64 | 1 | road projection: 32 segments × 5 `divu`, curve/hill from track bytes `$a851a` |
| `$89d20` | 2.49 | 1.09 | 1 | roadside objects and actors → draw list; frame-tied animation `$a5990` |
| `$8c5a8` / `$8c8ae` | 2.39 / 1.13 | 0.92 / 0.92 | 1 / 24.6 | actor-versus-actor collision loop; pairwise proximity test |
| `$b16d6` | 2.24 | 2.09 | 1 | 150-line loop ANDing a mask into plane 2 (roadside edge shading; guess) |
| `$8b02e` / `$8b29a` | 2.22 / 0.73 | 1.16 / 0.66 | 1 / 9.4 | draw-list projection/clipping of scenery, per-object scale |
| `$b076e` / `$b0be2` | 2.02 / 1.07 | 0.79 / 0.67 | 1 / 11 | after swap: copper sky/horizon section and hardware sprite control words |
| `$b0db4` / `$b0de6` / `$b0e92` | 1.94 / 1.65 / 1.29 | 0.28 / 0.36 / 1.26 | 1 / 15.8 / 2.5 | per object: swap patch words into shared rider frames (colours/faces; guess) |
| `$89048` | 1.61 | 1.59 | 1 | road colour-stripe line list (75 lines) |
| `$b537e` / `$b5498` | 1.61 / 0.19 | 0.22 / 1.26 | 4 | music player (L6) |
| `$88cea` / `$b0c8a` / `$b4c8e` | 1.49 / 1.41 / 1.35 | 0.07 / 0.01 / 1.30 | 1 / 1 / 2 | damage bars; two dials; 64×16 4-plane fill/clear + copy (8 blits per call, fill/clear likely redundant) |
| `$b3740` / `$b37a0` / `$b49d6` | 1.47 / 1.32 / 1.25 | 0.14 / 0.07 / 1.23 | 2 / 7 / 7 | HUD text, 8×8 font `$b95c8`, CPU byte writes |
| `$8bbe6` | 1.17 | 0.77 | 6.5 | actor position on track (curve/hill lookup), full `movem` |
| `$8b37e` | 0.93 | 0.90 | 1 | draw-list insertion sort |
| `$aeed6` / `$87040` | 0.93 / 0.70 | 0.09 / 0.21 | 4 | per-field: fader, sound effects, game hook |
| `$8a716` / `$8a83c` | 0.85 / 0.51 | 0.82 / 0.45 | 6.5 | actor sprite scale/position (4 `divu` + 4 `mulu`); sprite frame selection |
| `$8c130` / `$8c48e` | 0.81 / 0.61 | 0.35 / 0.60 | 1 / 7.5 | player interaction (collisions/fights); response with a 16-register `movem` |
| `$b38e2` / `$b3a30` | 0.53 / 0.26 | 0.26 / 0.26 | 2 / 18.6 | Bresenham needle lines |
| `$b45f8` | 0.49 | 0.49 | 2 | needle background restore (4 blits) |
| `$b527e` | – | 0.47 | 8 | L6 handler |
| `$8dd66` | 0.47 | 0.45 | 7.4 | per-actor acceleration from the bike table `$9434c` |
| `$b381a` / `$b4b3e` | 0.43 / 0.41 | 0.02 / 0.41 | 1.8 | second-font text |

### What limits faster CPUs
- **68000:** CPU-bound at 5–6 fields per frame. Every CPU item in F helps; caches don't
  exist.
- **68020/030 without caches:** every instruction fetch is a chip access (1.5 chip accesses
  per instruction, 18.9 cycles per instruction measured in the trace), plus 0.75 field per
  frame of stalled blits. Caches alone gain 4 → 3 fields per frame.
- **040/060:** frames take 2–3 fields. Roughly 0.75 field per frame is blits with the CPU
  frozen (`BLTPRI`, everything in chip). The rest is chip-bound CPU work (all data and
  stores in chip; on these CPUs code may hit the cache, A3b). CPU speed barely matters:
  060/50 ≈ 040/25.
- **The floor for 2 fields per frame:** blitter time must overlap CPU work or shrink, and
  the CPU's chip accesses must fall. **50 fps (1 field)** needs blits under about 0.5 field
  and fully overlapped, with the CPU working from fast RAM.

## 7. Plan

Each item lists its steps, its check, and the expected effect. Run every change through the
item A2 matrix and the item A4 equivalence check before moving on. Every new behaviour is
a slave option whose default reproduces the original timing until G1 decides the defaults.

### A. Harness and baseline — complete (2026-10-20; evidence in §9)
- **A1 Fixed race scenario.**
  - A1a Keep `to_race` as the machine-independent route. Add a settle point at race field
    100 and a fixed seed check (DETERMINISTIC boots repeat exactly).
  - A1b Record an input tape for 30 s of a lap: throttle, steering through curves, one
    overtake, one collision and one crash. Replay it through `monitor input` at race
    fields, not boot fields.
  - A1c Store fixtures and expected results under the ignored harness. Never in the
    repository.
- **A2 Machine matrix.**
  - A2a `tools/matrix.sh` cells as in §3. Add `a1200-fast` with `NoCache` and a 040/060 MMU
    functional boot (correctness only; its timing is not comparable).
  - A2b Per cell, record: fps, the fields-per-frame histogram, distance @490 race fields,
    and screenshots at fixed race fields.
  - A2c Give each cell a deadline, so a hung cell fails instead of blocking the matrix.
- **A3 VERIFY slave instruments** (`-DVERIFY` build only).
  - A3a A frame counter and fields-per-frame histogram in slave memory, read by the
    harness. This replaces the mod-3 rotation sampling.
  - A3b Log inherited `CACR` after `resload_Control` and at race start, on 020 and later
    only. The baseline has no `resload_SetCPU`; D1 must add a post-SetCPU reading when it
    introduces that call.
  - A3c Snapshot `DMACON`.
  - A3d A game-state hash (player and actor records, ranks, clock) at fixed race fields,
    for A/B equivalence.
- **A4 Equivalence check.**
  - A4a Speed calibration: compare distance at completed simulation boundaries
    after identical applied input durations, within ±1% of the reference cell.
    Document start/end boundaries and preserve actual input timing. The user
    approved separating this from input/display latency (2026-10-21): retain
    the original fixed-live-field measurements as reported diagnostics, and
    independently require the existing visible-response safeguards, 50 Hz
    elapsed-time accounting, no dropped time and cadence-invariant outcomes.
    This approval does not automatically accept an experimental candidate.
  - A4b A1b tape: compare native rank order and crash count against B. For C,
    the user approved intentional differences caused by documented corrections
    to render-dependent logic (2026-10-21). Establish and review the corrected
    handling baseline; require identical outcomes across render cadences at
    identical simulation boundaries. Do not attribute unexplained differences
    to RNG or accept a changed outcome merely because a test passes.
  - A4c Visual: review screenshots at fixed race fields against B. Document
    scene differences arising from approved handling corrections; require
    correct rendering of the resulting state, with no unexplained artifacts.
- **A5 Profiles.**
  - A5a Repeat the 020 Barto trace after each phase.
  - A5b Use aprof without an MMU for flat per-PC execution counts and chip-access time
    on 030/040/060, where the Barto trace is empty. The emulator does not model real
    040/060 instruction-cycle costs; do not interpret these as hardware cycle profiles.

### B. Correctness fixes and risks — complete (2026-10-20; limits in §10)
- **B1 Slave `test_for_pause` stack bug — complete (2026-10-20).** It saves `d0-d1/a0` (12 bytes) but restores
  `d0-d2/a0` (16 bytes). When the stick is idle, `$87298` returns from the slave to its
  caller's caller with `a0` corrupted, and the keyboard pause test and the rest of the
  per-field steering after `$872b4` are skipped.
  - B1a Restore `d0-d1/a0`.
  - B1b Verify: with the stick released, steering recentres as in the original game logic,
    keyboard pause works, and the CD32 PLAY pause works.
  - B1c Check that A4 still passes. The fix changes behaviour on idle-stick fields, so
    record the new reference.
  - Result: balanced register restore and key comparison before restoring `a0`.
    Keyboard Space and CD32 PLAY pause/resume freeze the race clock; released steering
    recentres (840 to 0 in 40 fields). The normal A1b replay retains exact screenshots,
    final rank order and one crash. All ten previously working normal matrix cells
    pass and stay within 1% of their A distance; the twelve diagnostic/functional
    cells pass. Uncached 030 remains B2. Accepted B1 evidence: ignored
    `tmp/dev/tmp/b1-{input-run2,pad6,replay-run,matrix-run,normal}`.
- **B2 030/50 uncached crash — complete (2026-10-20)** ("Illegal Instruction ($10) at $68" in the front end).
  - B2a Reproduce it, and find the boot field and the screen it happens on.
  - B2b Break on the exception. Find the code that jumps into the vector table: likely a
    timing race (blitter or beam) or a CPU-speed delay.
  - B2c Fix it in the slave, or document it if it is emulator-only (cross-check on the
    x86_64 FS-UAE).
  - Result: the previous screen blit overwrote the preloaded dashboard image before
    its CPU copy completed. Wait for DMA before loading files. Before the fix, 2300
    bytes of `DASH2.LBM` were corrupted; afterward all 7824 bytes match the asset.
    The bad RLE stream overwrote code and led to the reproduced Line 1111 exception
    at $4. The historical $68 report was not reproduced. The failure occurred during
    dashboard preparation, around monitored boot fields 2400–2440. This is a game/
    preload synchronization fix, not an emulator-only exception. Evidence: ignored
    `tmp/dev/tmp/b2-{load,copy,rle,fixed-copy,matrix,normal,replay}` and
    `tmp/dev/docs/b-correctness.md`.
- **B3 Frame-tied animation `$a5990` — complete (2026-10-20).** Patch `$89d32` to derive the phase from the race
  field counter (`($a5d4c >> 2) & 7`) so that it matches today's 4-fields-per-frame look at
  any rate. Check it visually at 12.5 and 25 fps.
  - Result: `CUSTOM2` bit 0 enables the field-based phase; default remains original.
    VERIFY records the field and phase at the hook. All 250 sampled phases match
    `(field >> 2) & 7` at 12.5 fps and exactly 25 fps, with scenes visually checked.
    The 25 fps run uses a fast functional 68020 configuration, not a hardware speed
    claim. Evidence: `b3-animation-020`, `b3-animation-25-run`, `b3-normal-on`,
    `b3-retry`, and `b3-replay-on` under the ignored harness output directory.
- **B4 Small deltas — complete with a two-field safety floor.**
  - B4a A VERIFY option that renders only every Nth frame, or skips `$afd60`, to force
    delta 1 and 2 on a 68020.
  - B4b Compare distance, AI outcomes and collisions with the A1b tape against delta 4.
  - B4c If rounding loss appears, add a fractional carry or clamp the minimum delta (for
    example run the logic twice at delta 2 instead of once at 4). Also add an upper delta
    clamp (for example 8) for load hiccups.
  - Result: delta 1 fails the straight-distance tolerance (-1.083% versus delta 4);
    delta 2 is within it (-0.908%). The collision tape changes outcomes at both
    smaller steps, so cross-rate trajectory equivalence is not established.
    `CUSTOM2` bit 1 enforces a real two-field minimum by waiting at the swap,
    rather than artificially increasing the simulation delta, and caps long steps
    at 8. A protected one-field-speed run exactly matches the delta-2 terminal
    state. A 12-field-frame control uses delta 12; the option limits it to 8.
    This implements the permitted minimum-delta mitigation; 50 fps is not approved.
- **B5 Unexplained paths — complete.** Watch `$8aff0` (paced drain of `$a8722`) and the `$875bc` gate in
  a crash and at 25 fps. Confirm they can't throttle or stall at high frame rates.
  - Result: zero closed gates and zero drain calls in the 020 crash replay (399
    gate checks) and a full-render 25 fps crash/recovery run (1204 checks). The
    latter needs a different input tape to actually crash. `$a8722` remains zero
    in these scenarios. If populated, its producer caps the queue at 6400 and
    `$8aff0` drains at most 3000 per field: at most three drain fields before the
    following consumption. It is an intentional bounded delay, not an unbounded
    wait. No gate/drain patch is needed for the supported 25 fps target.

### C. Consistent simulation with uncapped vsynced rendering — complete (2026-10-21)

C1–C3 are implemented and validated under the approved A4 speed/handling rules.
The 20,616-byte runtime uses 20 ms PAL simulation steps and historical field
inputs, rendering the latest completed state through native vsync. The default-off
`CUSTOM2` boolean selects this only on 68020+ with suitable Fast RAM. No frame
limiter or delayed interpolation is added. B's optional floor/clamp is replaced
only on this selected path; unsupported machines retain original timing.

The final movement correction preserves the original four-field displacement
convention through one-field updates, without changing acceleration or backdating
input. Road movement retains fractional carry. Actor-width lane occupancy replaces
render-register residue; simulation owns AI, collisions, poses and sound events.
Forward heading prediction affects presentation only. Fast code, scratch and stack
reduce the cost of running consistent simulation. These intentional corrections
can change opponent paths and crash outcomes relative to B; they are not RNG excuses.

All nine accelerated cells meet A4a's ±1% distance tolerance at documented equal
input durations of 398–400 fields; worst error is 0.328368%. Original live-field
measurements remain diagnostics, including -1.1762% default-020 and -1.4668%
NoCache-020. The new calibration does not claim every tiny startup displacement
matches B's variable-step integration. The [dependency audit](simulation-timing.md)
records the full trajectories, approved scope and exact executable hashes.

Every measured visible-response phase meets its same-cell B limit: cached 020
180/160/140/120 ms repeated (median 150, maximum 180); 040 140/120 ms repeated
(median 130). These are field-capture estimates with one-field boundary uncertainty.
No timing-policy change was made merely to improve the old live-field diagnostic.

Fresh short replays match all 1595 common state hashes, sound events and six capture
regions at 1/2/3/4-field and varying 2/3/4/12/16-field render intervals. One-field
coverage omits drawing. Full finish and arrest replays match across cadences and
restart cleanly. A controlled damage-31 fixture reaches damage 33 through a native
collision, displays WRECKED, exits and restarts identically. Natural crashes and
recovery are exercised; an unmodified zero-damage-to-WRECKED run is not established
for this final runtime. The earlier lane-only natural-wreck result is not reused
as proof for the final binary.

Keyboard/CD32 controls, pause/resume, both demo exits and enhancement-off checks
pass. All eleven normal hardware cells and two MMU functional cells pass; A500 and
Chip-only fallbacks match B's sampled state, deltas, distance and rate exactly.
MMU tests disable data-cache emulation and do not prove hardware cache coherence.

Current rates: A500 8.5 fps; Chip-only 020 12.5; Fast 020 default/Cache 12.5,
NoCache 8.3; 030 16.7; 040 22.8; 060 23.3. Sampled median simulation-step cost is
approximately 7.69/8.91 ms on default/NoCache 020, 4.94 ms on 030, 3.91 ms on 040
and 3.59 ms on 060. These are short emulator beam samples, not worst-case hardware
bounds. C completes independent simulation; D–F still own further speedups and
throughput targets, including the remaining 020 regression against B.

Render as fast as the machine can, presenting completed frames at vsync. There are
no fixed-rate or adaptive frame-limiter modes. Simulation speed and outcomes must
not depend on how many frames are rendered. B4's variable-delta results show that
this requires simulation work, not just removing its optional two-field floor.
Use separate hardware paths: retain original timing on the 68000; target the new
50 Hz simulation at 68020+ machines with Fast RAM. A500 simulation cost must not
dictate the accelerated path's timestep.

- **C1 Separate simulation from presentation.**
  - C1a Audit the race loop, per-field input/clock hook, all delta consumers, and
    the producer/consumer record handshake. Identify simulation state updates,
    rendering preparation and side effects currently executed once per frame.
  - C1b Target one PAL field (20 ms, 50 Hz) per simulation step and measure its
    cost on accelerated CPUs. Optimize its cost before considering a larger step;
    report A500 compatibility separately. Use elapsed active fields; preserve
    pause, the existing PAL clock rate and input timing. Do not equate one rendered
    frame with one simulation step.
    Normalize per-call effects such as crash-camera decay against the original
    timing reference; render-rate invariance alone does not prove correct speed.
  - C1c Specify ownership of actor state, collision/AI updates, animation, sound
    events and render buffers so extra renders neither advance gameplay nor
    duplicate side effects. Capture input at field boundaries for simulation use.
- **C2 Implement independent timing.**
  - C2a Advance simulation in consistent steps, consuming accumulated game time.
    Run the required steps before rendering; preserve remainder time. Handle slow
    frames without silently discarding elapsed time or using a different step size.
  - C2b Render the latest available simulation state as often as possible. Use
    forward extrapolation if needed for smooth motion between steps, isolated from
    authoritative gameplay state and collision tests. Delayed interpolation and
    an added 80 ms presentation or input delay are explicitly rejected.
  - C2c Retain the original safe vsync/copper buffer handoff without extra pacing
    waits. Replace B's optional presentation floor and delta-clamp mitigation only
    when the independent simulation passes validation. No new frame-limiter option.
  - C2d Select the accelerated path only after verifying CPU and Fast RAM
    availability. Preserve the original path on unsupported configurations,
    including 68020+ without Fast RAM; test both dispatch and fallback.
- **C3 Verify.**
  - C3a Replay identical field-timed input at render intervals of 1, 2, 3, 4 and
    varying/longer intervals. Compare simulation state, distance, clock, opponent
    order, collisions, crashes and event counts at identical simulation boundaries.
  - C3b Run A2/A4, review deliberate presentation differences, and verify pause,
    resume, attract-mode demos and their exits, race transitions, keyboard/CD32
    controls and per-field input response.
    Measure input-to-display latency explicitly. Retain original-behaviour
    comparisons; explain any intentional baseline change.
  - C3c Measure rendering throughput and simulation cost on the A500 through 060,
    plus MMU functional checks. Confirm that no artificial frame cap remains and
    that missed rendering deadlines do not change simulation speed.
- **Expected:** faster machines show more frames of the same simulation. Actual
  throughput gains still depend on D–F; 50 fps needs both sufficient rendering
  performance and the cross-rate simulation checks above.

### D. Caches, bus priority and memory
- **D1 Enable caches from the slave.**
  - Emulator implementation and cache-state/page-policy checks are complete;
    real-hardware coherency validation remains pending by agreement. See
    [memory-performance.md](memory-performance.md) for the audit and evidence.
  - D1a Call `resload_SetCPU` on the selected enhanced path: instruction cache on
    (and data cache on 030 and later). Respect `NoCache`; use the single
    "Enhanced framerate" master toggle, with no additional user-facing cache option.
    Implemented in the enhanced runtime, with `VERIFY_C_CACHE` retained for
    explicit diagnostic selection. Automatic 020/030 caching reaches the existing
    cached rates; off/Chip fallback, the full normal matrix, keyboard/CD32,
    full-finish/restart and MMU page-policy checks pass.
  - D1b Call `resload_FlushCache` after every file load and decrunch (`ReadSomeFile`, the
    loader patches `$496A`/`$4DCA`/`$4800`/`$4844`/`$8E58`) and after `resload_Patch`.
    The WHDLoad load/decrunch/patch APIs already flush on return. The native Ice!
    depacker now has its own gated return-path flush; code-copy initializers flush too.
  - D1c Read `CACR` back (A3b) on 020/030/040/060. Find out why `Cache` had no effect on
    040/060 without an MMU (caches already on, or ignored).
    Immediate post-SetCPU snapshots now pass across 16 configurations. Default
    040/060 CACR already enables both caches; page policy and hardware cache-inhibit
    signals remain distinct from the register, and emulator timing is not board timing.
  - D1d Coherency: chip buffers that the CPU writes and the blitter or copper reads (screens,
    copper list `$147e`, sprite data, bob masks) must not sit in a copyback cache. Verify on
    040/060 with WHDLoad's chip-memory cache mode, and with the `MMU` option functional
    boot.
    All user/supervisor BaseMem pages are verified write-through on 040/060,
    with data-cache emulation both disabled and enabled; Fast code/stack use copyback.
  - **Expected:** 020 12.5 → 16.7 fps, 030/50 → 16.8 fps (measured with WHDLoad `Cache`).
- **D2 Turn off blitter priority in the race.**
  - Complete for the current memory layout: enable CPU/blitter sharing only on
    enhanced 040/060, and restore the original priority on race/demo exit.
    All-cell measurements and full-race equivalence are in memory-performance.md.
  - D2a Find who sets `BLTPRI`: DMACON writes are `$a879a #$8280`, `$a882e #$8220`,
    `$af224` and `move.w d1`; `$aeacc` clears it but has no callers. A VERIFY DMACON watch
    will tell.
  - D2b Option: clear `BLTPRI` at race start (and keep it clear).
  - D2c Measure on all cells. With caches on (D1), the CPU can then execute from cache and
    fast RAM, and get chip slots, while blits run.
  - D2d Check the A500: with `BLTPRI` off the 68000 steals slots and blits get longer.
    Keep it on for the 68000 if slower.
  - **Expected:** a large share of the 18.8% stall becomes overlap on 020+ once D1 is in;
    measure.
  - The temporary startup copper list is the original setter. The complete D
    matrix confirms no benefit on 000/020/030 and a modest gain on 040/060.
    Retain native priority on 000/020/030; remeasure after D3/E changes the workload.
- **D3 Relocate everything eligible to public RAM** (fast RAM preferred when available).
  - **Main-image progress:** enabled Fast-RAM paths now move the complete
    246,764-byte main code/data image into an optional 388 KiB public allocation,
    retaining DMA heaps in Chip. This reservation includes
    CPU image-description tables and music patterns. This includes native 68000 code/data and stack,
    with its original simulation retained. Main-image relocation, full-race equivalence,
    fallback, MMU, controls and visible-response checks pass in emulation. This
    does not close the low-memory, mixed-asset or broader-selection
    audit below. Loader/title/intro CPU code/data and a separate guarded
    boot stack now also use public RAM; their Chip copper lists stay in place. See memory-performance.md for exact evidence and limitations.
  - D3a Audit all loaded code, data and stacks, including menus, race logic, rendering,
    interrupts and audio routines. Classify each region by CPU/DMA access, lifetime,
    references and relocation constraints. Account for every region; document why any
    region must remain in chip RAM rather than limiting the move to measured hotspots.
  - D3b Add `ws_ExpMem` for the eligible working set, with public-memory allocation
    semantics (fast preferred, chip fallback). Size it from the audit, preserve the
    original path when expansion memory is unavailable, and verify the actual placement.
    Check memory requirements and behaviour on machines without fast RAM, including the
    1 MB chip A500; do not assume that a fallback allocation leaves enough chip memory.
  - D3c Relocate all eligible executable code. Start with the road rasteriser
    `$b10d0-$b19ff` and geometry `$8970e-$89b30`, `$89656`, `$89048`, then cover the rest.
    Fix absolute and PC-relative references, internal calls/jumps, entry points, vectors
    and function pointers. Account for interleaved data and later loads/decrunches;
    preserve slave patches and cache flushing for every relocated module.
  - D3d Relocate all CPU-only mutable state, tables and assets, including projection
    outputs `$a6f3c-$a803e`, the reciprocal table `$89b1e`, track data, actor records and
    draw lists. Audit every reader/writer and stored pointer; maintain one authoritative
    mutable copy. Mixed CPU/DMA regions must be split where practical, with explicit
    transfers if a CPU-side copy is useful (including E5's images and masks).
    The actor-memory audit identifies a concrete lifetime conflict: `$a5d60..$a6edf`
    holds race actors, but graphics loaders reuse `$a5de0` and its image pointers
    must be classified by consumer. The D3 portrait audit establishes CPU copying
    from that scratch into Chip screens; the full-image move includes this
    lifetime. Remaining image consumers still need explicit classification.
    A race sample attributes 10.779% of CPU bus records to
    this region; it is a relocation candidate, not a proven throughput gain.
  - D3e Move the CPU stack and any separate interrupt stacks into the allocated memory.
    Audit stack bounds, startup/switching, exception/interrupt entry and exit, and quit
    handling; retain a valid stack throughout loading and relocation.
    The enhanced runtime now uses the tested optional Fast RAM CPU stack as a C
    cost reduction; guards, CD32 pause, 040/060 MMU and real quit paths pass.
    This does not close the remaining relocation work or establish a universal
    worst-case stack bound; see the runtime stack evidence in simulation-timing.md.
  - D3f Keep DMA-accessed storage in chip RAM: screen buffers, copper lists, hardware
    sprite data, audio samples and blitter sources, masks and destinations. Reclaim old
    chip storage only after proving that no live reference or later loader uses it.
  - D3g Verify relocation with A2/A4, cache/MMU checks and menu/race/load transitions.
    Record chip/public-memory usage, actual fast-RAM placement, residual chip accesses
    and the audit's remaining exceptions. Cover fast-RAM and fallback configurations;
    choose CPU-specific defaults from measurements rather than excluding the 68000.
  - **Expected:** less chip traffic throughout the game; a 2–4× faster road and geometry
    on 030/040/060 remains an estimate. Measure the broader benefit and memory cost.
    Do this after D1/D2 have been measured.

### E. Blitter work and overlap
- **E1 Overlap the background clear with the road.**
  - E1a Start the `$b1744` blits through a queue, then run `$b10d0`. They touch disjoint
    memory: the road writes planes 0/1 below the horizon, the clear writes planes 0–3 above
    it and planes 2/3 below.
  - E1b Needs `BLTPRI` off (D2) for the CPU to proceed.
  - **Expected:** up to 8% on the 020. On fast CPUs the saving equals the road time.
- **E2 Blitter queue.**
  - E2a A ring of blit descriptors executed by a level-3 blitter-done handler. The game has
    a dormant ring at `$aeb84` with handler `$aead6`; reuse its idea, but run in the slave.
  - E2b Queue the bob blits (`$b3ba2`) so that `$afe12` prepares the next object while the
    blitter draws.
  - E2c Keep the synchronous path for the 68000 if the interrupt overhead costs more than
    it saves (measure).
  - **Expected:** a further 5–7% on 020; most of the remaining stall on fast CPUs.
- **E3 Precompute bob masks.** Drop blits 1–2 of 6 per bob.
  - E3a Build a mask plane per image/LOD at load time into chip RAM. Check the chip budget:
    1 MB machines may not fit, so make it an option for 2 MB chip.
  - E3b **Expected:** about 1.7% of CPU on 020, and about 30% of the bobs' blitter channel
    time.
- **E4 Remove redundant blit work.**
  - E4a Skip clearing lines that the opaque mountain/hill copies overwrite anyway: 1–2%.
  - E4b Clear only the sky regions dirtied by last frame's bobs in this buffer (dirty
    rectangles from the bob clip results): 2–4%.
  - E4c Drop the fill/clear before the full-mask copy in `$b4c8e` (dials) after checking
    that the copy covers the rectangle: 0.55%.
- **E5 040/060 CPU cookie-cut** (stretch). With sources and masks in fast RAM, draw bobs
  with the CPU instead of the blitter on 040/060. Keep the blitter path elsewhere.

### F. CPU work reduction (all CPUs; the 68000 depends on it)
- **F1 Road rasteriser** (`$b10d0`/`$b1994`, 21.7%).
  - F1a Remove the duplicated loads (`$b19aa/$b19b0`, `$b19b6/$b19bc`, `$b13d2/$b13d8`,
    `$b13dc/$b13e2`).
  - F1b Replace the per-word flag tests and `movem` in `$b1994` with a precomputed
    edge-word table per stripe state.
  - F1c Merge the plane 0/1 span loops.
  - **Expected:** 4–6%.
- **F2 Road geometry** (`$89a9c`/`$89ac8`/`$89656`/`$89048`/`$8970e`, 13.3%).
  - F2a Merge the four edge passes and the per-line pass into one scanline walk.
  - F2b Unroll the DDA.
  - F2c Use one reciprocal per segment in `$8970e` instead of 5 `divu`.
  - **Expected:** 4–6% on 020, more on the 68000.
- **F3 HUD** (`$88610` + `$88cea`, 6.2%). Redraw digits, needles, dials and position only
  when the value changes (per buffer, so twice). Clear the mirrors with the blitter or skip
  unchanged mirrors. **Expected:** 2–4%.
- **F4 Object dispatcher** (`$afe12`). Replace the type `cmpi`/`bcc` cascade with a table.
  **Expected:** 1.5–2%.
- **F5 Small items.**
  - F5a Trim full-register `movem` in per-actor helpers (`$8bbe6`, `$8a716`, `$8c48e`,
    `$8b9aa`, `$8b02e`, `$8b37e`): 1.5%.
  - F5b Collision early-out on the track-position difference: 1–2%.
  - F5c Seed the depth sort with last frame's order: 0.5%.

### G. Integration and release
- **G1 Options and defaults.**
  - G1a Keep every framerate enhancement behind the single `CUSTOM2` boolean
    "Enhanced framerate": simulation timing (C), caches (D1), `BLTPRI` (D2),
    public-RAM relocation (D3), queue (E2), and CPU optimizations (F).
    Off retains original timing/rendering; CUSTOM1 stays the password.
    Hardware selection occurs within the enabled path, not as extra user toggles.
  - G1b Pick per-CPU defaults from the A2 matrix: no change on the 68000 unless it is
    faster.
- **G2 Verification set.** One pass per change: A4 equivalence, an A2 matrix row, the B1
  pause/steering check, an MMU functional boot on 040/060, and a 1 MB chip A500 boot to the
  race.
- **G3 Documentation.**
  - G3a ReadMe: options, the measured fps table, the original-timing switch.
  - G3b Update this plan's status and measurements.
- **G4 Release.** Bump the slave version, build the installer archive, and commit.

### Order and milestones
1. A1–A4, then B1–B3: harness and fixes. Milestone: verified references.
2. C separates simulation timing from rendering. D1/D2 measure caches and blitter
   priority; the 020+fast throughput target is at least 16.7 fps.
3. E1–E4. Milestone: 030/50, 040 and 060 rendering fits in two fields without a
   frame limiter; simulation timing remains independent of rendering throughput.
4. D3 and F pursue 50 fps throughput and an A500 above 10 fps. Replace B4's
   temporary safety floor only with validated independent simulation timing.
5. G.

## 8. Open questions
- How much 040/060 chip wait can D2 overlap? A5b records flat chip-access time, with
  the largest entries in frame/blitter polling; it cannot establish hardware CPU cost.
- A3b resolved the register state: 040/060 CACR is `$80008000`, or `$00008000` with
  `Cache`; fps is unchanged. Actual data-cache emulation is disabled in these baseline
  configurations, so D1 still needs coherency and hardware validation.
- B2 resolved the reproduced 030 crash as DMA overwriting a preloaded image.
- C resolves the fixed-step choice at 20 ms, with documented displacement and
  render-dependent handling corrections. D–F pursue the remaining throughput
  targets without changing that step or adding a frame limiter.
- What is the free chip RAM in the race on 1 MB machines? It decides E3 and the queue
  buffers.
- Could an optional clock correction provide NTSC-correct timing? Out of scope here; noted
  because the clock already runs at 5/6 speed on PAL.


## 9. A completion and accepted baseline (2026-10-20)

All A items are implemented and exercised. This completes the measurement infrastructure,
not the correctness fixes in B or the performance changes in C–F. The normal slave is
byte-identical to the pre-A build (SHA-256
`5c85f98b820abbf02af5bdf6696b1111321e0942047fc0739a6c60226bb138da`).
Only `VERIFY` builds contain the new hooks and storage in `verify.s`.

| Completed items | Evidence in ignored `tmp/dev/` |
|---|---|
| A1a–c | `fixtures/lap.json`: exact field-100 start, 1,500 PAL fields of throttle/steering, overtaking and a roadside collision/crash; local fixture manifest and expected states/screens |
| A2a–c | `tools/matrix.sh`, `tools/matrix_a.py`: normal and diagnostic matrices, NoCache, MMU functional cells, per-cell deadline and retained failure logs/screens; intentional one-second timeout rejected |
| A3a–d | `verify.s`: frame count, completion-interval histogram, inherited/race CACR, initial/frame DMACONR, fixed-field clock/actor/rank hash; independent rotation counts agree in every passing diagnostic cell |
| A4a–c | `tools/compare_a.py`, `tools/validate_a.py`: ±1% distance, final full racer order/crash count, fixed-field screenshots; normal/VERIFY/hash repeat pairs pass; five corrupted controls rejected |
| A5a–b | `tools/profile_a.py`, `tools/profile_matrix_a.py`: 020 Barto and 030/040/060 flat aprof, with effective CPU configuration and binary provenance |

Authoritative local report: `tmp/dev/docs/a-baseline.md`; commands and instrumentation ABI:
`tmp/dev/docs/development.md`. Raw game data, traces, screenshots and reference fixtures
remain ignored. Accepted run directories are listed in `tmp/dev/fixtures/a-reference.json`.

### Fixed-field matrix

Race fields 100–600, throttle held; distance is field 590 minus field 100. Histogram entries
are completed frames by field duration, measured by VERIFY; normal fps/distance come from
the uninstrumented slave. Do not mix the normal and VERIFY references for an A/B comparison.
The earlier §3 window differed, so its fps values are not directly comparable.

| Cell | Normal fps | VERIFY fps | Normal distance @490 | VERIFY histogram |
|---|---:|---:|---:|---|
| `a500-1m` | 8.5 | 8.5 | 3,425,028 | 5: 9, 6: 76 |
| `a1200` | 12.5 | 12.5 | 3,337,152 | 4: 124, 5: 1 |
| `a1200-fast` | 12.5 | 12.5 | 3,364,352 | 4: 124, 5: 1 |
| `a1200-fast+cache` | 16.6 | 16.5 | 3,347,896 | 3: 159, 4: 6 |
| `a1200-fast+nocache` | 12.5 | 12.5 | 3,364,352 | 4: 124, 5: 1 |
| `030-50` | failed | failed | — | front-end exception at A baseline; fixed in B2 |
| `030-50+cache` | 16.6 | 16.6 | 3,341,412 | 3: 166 |
| `040-25` | 22.6 | 22.7 | 3,345,638 | 2: 179, 3: 48 |
| `040-25+cache` | 22.6 | 22.7 | 3,345,638 | 2: 179, 3: 48 |
| `060-50` | 23.2 | 23.3 | 3,335,284 | 2: 200, 3: 33 |
| `060-50+cache` | 23.2 | 23.3 | 3,335,284 | 2: 200, 3: 33 |
| `040-mmu` | functional only | functional only | — | TC=$8000; no timing comparison |
| `060-mmu` | functional only | functional only | — | TC=$8000; no timing comparison |

Diagnostic matrix: 12/13 passed. Normal matrix: 10/11 passed. Both correctly return failure
for uncached 030; it is not waived or counted as a pass. The validated no-MMU 030 uses the
`68EC030` CPU selector. Its failure screenshot reports **Line 1111 Emulator ($2C) at $4**
at the AmigaDOS prompt, distinct from the earlier Illegal Instruction at $68 report.
A did not establish a shared cause or implement a fix. B2 later resolved the
reproduced loader/DMA corruption; the historical $68 report remains unconfirmed.

### Acceptance boundaries and findings

- Host joystick mappings must be disabled (`JOY0=none`, `JOY1=none`). `DETERMINISTIC=1`
  alone did not isolate the replay from host input. Monitor input now drives the tape.
  Repeated boots match the complete initial actor/clock/rank state; this is the seed/state
  check, without inventing an unidentified RNG address.
- Normal and diagnostic 30-second replays each repeat with the same final racer order,
  one crash, and byte-identical scheduled screenshots and checkpoint states. Two normal
  intermediate samples differ at debugger stop phase; arbitrary per-two-field RAM snapshots
  are not promised identical. The separate slave hash is captured inside the field tick at
  field 590 and repeats exactly. Hashing is excluded from performance runs.
- Distance tolerance remains ±1%. It applies to the same machine/build mode before and
  after a change. Cross-CPU equality is not established by this baseline: the normal A500
  differs from the normal 020+fast by about 1.8%. Diagnostic overhead also changes phase
  and can exceed that tolerance (A500). Neither discrepancy is silently accepted as an
  A/B pass. The original 0.7% observation in §4 was specific to its exploratory window.
- Visual comparison fails closed on any different or missing scheduled screenshot. A future
  intentional rendering/timing change needs an explicit scene review and a new reference;
  matching final rank alone is insufficient.
- CACR at startup/race: 020 `$0`, with Cache `$1`; 030 Cache `$2011`; 040/060 `$80008000`,
  with Cache `$8000`. DMACONR is `$07f7`, including BLTPRI. Unsupported 68000 CACR is `$ffffffff`.
  Equal 040/060 fps with different CACR is an emulator observation, not proof that hardware
  caches do not help. These configurations have `cpu_data_cache=false`.
- Both MMU cells execute the race and report TC `$8000` (translation enabled). They use
  `uaeboard=full` and disabled CPU data-cache emulation: `full+indirect` deadlocked in the
  native filesystem trap path. This is functional MMU coverage, not cache-coherency or
  hardware-timing coverage. D1d remains open.
- Barto covers 495 complete recorded fields within the 500-field elapsed window (each of
  five chunks omits its initial partial field): 284,204 cycles/field, no missing PCs;
  DMA shares CPU 31.8%, blitter 13.6%, free 27.9%. Raw chunks are compressed with verified
  decompressed SHA-256. Flat aprof captures 500 vsyncs per fast-CPU cell. Its unmatched
  return counts prevent trustworthy inclusive call costs; 040/060 costs are instruction
  and chip-access approximations, not real hardware cycles. Use flat PCs for subsequent
  comparisons and preserve these limitations.


## 10. B completion and supported timing (2026-10-20)

B1 fixes the idle-stick stack imbalance and retains the correct keyboard comparison.
B2 waits for screen DMA before file loading; uncached 030 now boots and races.
B3 makes spectator/roadside phase field-based. B4 tests the small-step limit and
provides an opt-in safety floor and ceiling. B5 finds no active gate/drain throttling
in the tested baseline and 25 fps crash scenarios.

The current user-facing option is the boolean **Enhanced framerate** (`CUSTOM2`):
omitted or `0` retains original timing; `1` enables the framerate enhancements.
The normal beta now selects C's independent simulation on 68020+ with Fast RAM,
without B's floor/clamp. Unsupported hardware retains original timing. Diagnostic
B builds retain the earlier timing safeguards for reference comparisons.
The older bit-0/bit-1 options documented in B's historical results are superseded.
Input/loading correctness fixes remain unconditional. The historical B safeguard
permits at most 25 fps and limits a delayed simulation step to eight fields; it
does not guarantee equal collision outcomes across frame rates. C replaces that
mitigation in the normal beta with consistent simulation steps. C is complete under the approved speed/handling criteria summarized in §7;
D–G remain open.

Small-delta functional tests use the same 68020 configuration with fast execution,
render skipping and field-based waits; they establish correctness limits, not real
hardware speed. Straight-line distance after 490 fields is 3,364,352 at delta 4,
3,333,820 at delta 2, and 3,327,906 at delta 1. The input tape produces one crash,
zero crashes, and one earlier crash respectively, with different opponent order.
The protected fast run exactly matches the delta-2 final state, rank order and crash
count. Full rendering at 25 fps also matches the render-skipped delta-2 final state.
This is why the earlier B safeguard stopped at 25 fps. Those results remain a
reference for C's simulation changes, not a frame-rate limit in the current beta.

B diagnostics are compile-time only: `VERIFY_B` counts gate/drain calls and simulation
deltas; `VERIFY_SKIP_RENDER` omits `$afd60`; `VERIFY_FRAME_PERIOD=N` requests a minimum
N-field frame. The latter accounts for the original swap's next-field wait and still
honours the safety floor when enabled. None is present in normal builds.

Detailed inputs, binary hashes, comparisons and captures stay in the ignored harness:
`tmp/dev/docs/b-correctness.md`; `b4-deltas`, `b4-guard-{straight,tape}`,
`b4-upper-{control,clamp}`, `b5-020-replay`, and `b5-crash-search/run-0-False` under
`tmp/dev/tmp`. Final matrix and replay evidence uses the `b-final-*` prefix. Original
A evidence remains unchanged and available for comparison.


Final B validation passes all 11 normal matrix cells and both 040/060 MMU cells.
Same-cell normal distance stays within 1% of the B2 reference, and both option-off
and option-on 020 tapes retain exact screenshots, final rank order and crash count.
Keyboard/CD32 pause and recentering pass with safe timing both off and on. The
normal build contains no diagnostic markers. Conditional patches require WHDLoad
17.2; a 17.2 run with both options passes, as do the main 20.1 checks. The repeated
020 Barto capture retains 12.5 fps and essentially the same DMA shares as A.
