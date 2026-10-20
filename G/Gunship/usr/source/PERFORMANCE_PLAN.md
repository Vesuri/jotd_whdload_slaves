# Gunship: performance analysis and plan for faster CPUs

Goal: make Gunship run smoothly on faster CPUs (68020–68060, fast RAM). Smooth means three
things here: game time runs at a fixed speed whatever the CPU, the frame rate goes up with the
CPU, and frames arrive at an even pace. The 68000 must keep working, but it is not the target.

Part 1 is the analysis the plan rests on. Part 2 is the plan. All code locations are offsets
into `gamemule` hunk 0 (`+xxxxx`, the numbering of the slave's patch lists). `Dxxxx` is an
offset into gamemule hunk 6 (data, also the `a4` base of the compiled C parts). `hN:xxxx` is
an offset into gamemule hunk N. ROM addresses (`$FCxxxx`) are Kickstart 1.3, which the slave
runs under KickEmu. This analysis covers the version handled by `pl_gamemule_658`.

## Part 1: analysis

### 1.1 How it was measured

Part 1 records the initial, uncontrolled measurements. The controlled baseline and
corrected measurement contract are documented under A below.

- **Route:** the shipped v1.2 slave runs under FS-UAE with a scripted keyboard and mouse route:
  1. Return in the intro.
  2. Vehicle identification: the top entry.
  3. Continue on the pilot, ops order, checklist and arming screens.
  4. In the cockpit, keys 1, 2 and 3.
- **Window:** 500 recorded fields over 524 elapsed fields (10.48 s PAL): each capture
  adds an unrecorded lead-in field. It covers the first take-off: F1 pressed ten
  times, then four 100-field captures. A corrects this to 500 elapsed fields.
- **68000 instrument:** cycle-exact Barto traces (FS-UAE gdb stub). The machine is an A500 with
  512 KB chip RAM and 8 MB fast RAM.
- **68020 instrument:** the same trace, on an A1200 with 2 MB chip RAM and 8 MB fast RAM.
- **68030/040/060 instrument:** AmigaXDev's exact per-PC cycle profiler (aprof), on cycle-exact
  cores without an MMU model:
  - 68030 at 50 MHz,
  - 68040 at 25 MHz,
  - 68060 at 50 MHz,
  - all on the same A1200 base.
- **Reproducibility:** two boots of the route gave identical instruction records.
- **Caveat: the mission differs between machines.** The game picks it with a timing-dependent
  random choice, so each CPU gets a different mission. Cross-machine numbers therefore compare
  similar take-offs, not identical scenes; the completed A2 baseline fixes this. The 68040 and 68060 runs happen
  to fly the same mission.

### 1.2 Program structure

`gamemule` is the flight program. `titlmule` and `scrnmule` (intro and menus) are not
involved in the flight.

- **Game code:** a mix of compiled C (small data through `a4`) and hand-written assembler with
  absolute addressing (globals through `a5` = `D38F6`). Code, globals and tables are all in
  fast RAM; every drawing target is in chip RAM.
- **Display:** one Intuition screen, 320×200, 5 bitplanes. There are five 320×200×5 bitmaps in chip
  RAM:
  - 0 and 1: the double buffer,
  - 2 to 4: source art (map, cockpit, symbols).
  - There is also a single-plane mask/TmpRas bitmap.
- **What is redrawn each frame:** the cockpit is copied into both display buffers once at mission
  start. After that only the 3D view (320×90) and the instruments that changed are redrawn.

**Simulation tick loop, `+0563A`.** Each pass runs one simulation tick:
- the tick counter `D3B94` +1,
- controls and the flight model,
- `+04288`, which renders,
- `+04E3C`, keyboard commands,
- `+0937C`, `+0979C`, `+09C5C`, `+09F74`: AI, weapons, damage,
- every 16th tick, `+07F80`.

**Render between ticks, `+04288`.** It renders `ceil(D1548 / D154A)` frames per tick. With the
shipped values 6 and 3 that is 2 frames:
- the first is interpolated half-way between the previous and the new state,
- the second is drawn at the new state.
- Interpolated: the camera (position, altitude, heading, pitch, roll), six effect objects and the
  instrument values.
- Every other world object moves only once per tick.

**Frame, `+05C04`**, in order:

| step | routine | work |
|---|---|---|
| 1 | `+084E2` | point the RastPort at the back buffer (`D4BB0` is the back-buffer index) |
| 2 | `+07A1C` ×2 | sine of roll and pitch |
| 3 | `+05F8E` | choose the 3×3 terrain cells for the heading octant |
| 4 | `+05CBE`/`+05D62` | build the per-axis premultiplied rotation tables |
| 5 | `+05EA4` | rotate the shared vertex palette (111 + 35 vertices) by table sums |
| 6 | `+077B8` | clear the view by painting sky and ground bands (`+0921C`), horizon wedge and line, attitude ball (`+090DA`) |
| 7 | `+060A8` | the 3D view (§1.4) |
| 8 | `+0468C` | moving map (re-checked every 8 frames, blitted on change) |
| 9 | `+06224` | effect objects (explosions) |
| 10 | `+0AA4C` | cockpit: overlay restore, readouts, needles, gunsight, TADS scope, tapes, bar gauges |
| 11 | `+09B9A`, `+0BE5A`, `+0A37C`, `+0BE2C` | effect spawn and animation, tracers, centre message |
| 12 | `+04496` → `+00B7C` | swap: Intuition MakeScreen + RethinkDisplay |

**VBL server, `+00F14`** (exec AddIntServer, pri −60). Every field it:
- increments the VBL counter `h2:001C`,
- runs `+04B48`: sound, timers, palette flash, sprites, the music driver,
- reads the joystick and mouse (`+01068`).

### 1.3 Game time (answer to "faster or smoother?")

**On a faster CPU the game runs faster.** It does not just run smoother.

- **One fixed step per tick.** Each tick advances the simulation by a fixed step, and a tick
  always renders 2 frames. Nothing scales the step by elapsed time.
- **Elapsed time is measured but thrown away.** `+04470` measures the VBLs elapsed per tick
  and passes them to `+02276`. That routine computes a frame rate, assuming 60 Hz, and the
  result is discarded.
- **No game code limits the frame rate.** The only wait is the WaitTOF inside Kickstart 1.3's
  RethinkDisplay. Frame times therefore round up to whole fields, with a hard limit of 50 fps
  (25 ticks/s).
- **timer.device is opened but never used.** It is opened at `+032A4` (UNIT_VBLANK) and never
  sent a request. The game reads no beam position, CIA timers or DateStamp.

Measured in the take-off window, in simulation ticks per second of emulated time:

| machine | fps | ticks/s | game speed vs A500 |
|---|---:|---:|---:|
| A500 (68000) | 5.3 | 2.7 | 1.0× |
| A1200 (68EC020) | 14.8–15.1 | 7.5 | 2.8× |
| 68030/50 (heavier mission) | 10.0 | 5.1 | 1.9× |
| 68040/25 and 68060/50 | 15.2 | 7.5 | 2.8× |

Even on the A500 a tick takes 16–20 fields depending on the scene, so game speed already
varies with what is on screen.

**What stays at real-time speed**, because the VBL server runs it per field:
- sound and music,
- warning-lamp blinking,
- the hit flash and the effect-spawn window `D42F7`,
- tracer cadence (`+0A37C`, at most every 4 fields),
- stick input accumulation.

**Per rendered frame instead of per tick:**
- bar gauges move 1 pixel per frame (`+0ADB6`),
- one effect spawns per frame while `D42F7` ≠ 0,
- the map is re-checked every 8 frames.

**The key with raw code 12 doubles game speed at the same frame rate.** Its handler at `+04EF2`
toggles `D1548` between 6 and 3, which switches the interpolated frame off.

### 1.4 How the 3D view is drawn

**Cell walk, `+060A8`.** It walks the 3×3 cells around the helicopter in two passes, in a fixed
cell order for each heading octant. There is no depth sort: painter's order comes from the cells,
then from object order within a cell.

**Per object, `+0625C`.** The position comes from palette vertex sums (table adds, no multiplies).
Then:
- cull against Z, the frustum and distance,
- pick the level of detail,
- draw the shape with `+063DC`.

**`+063DC`, per shape:**
- transform and project the vertices: `+06642`/`+066E8`, 2 `divs` each, roll applied as a shear;
- backface flags: `+06818`;
- near-plane clip and an edge cache: `+06792`;
- run the shape's primitive list.

**Lines.** `+08538` clips with Cohen–Sutherland (`+082EC`, `+08466`). Then `+08548` draws with
the blitter in line mode, one blit per bitplane. A plane whose colour bit is 0 still costs a blit,
with a clear minterm.

**Convex polygons:**
- `+08698`/`+089E4` build a per-scanline span table in fast RAM.
- `+08B6C` writes the spans into the single-plane chip mask with the CPU, then makes one masked
  blit per plane.
- `+08818` clears all 200 span rows for every polygon, although the view has 90, and
  blitter-clears the previous mask box.

**Frame clear.** `+0921C` blitter-fills the whole 320×90 view in 5 planes, as a sky band and a
ground band.

**Volume:** about 18 shapes, 112 vertices, 58 lines and 12 polygons per frame in the A500 window.
That makes about **250–300 blits per frame**.

**How the blitter is driven.** The game owns the blitter for the whole flight: OwnBlitter at
`+0867C`, DisownBlitter at `+0868C`. It writes `$DFF040–$DFF074` directly. Every blit is preceded
by a busy-wait on DMACONR BBUSY.

### 1.5 Where the time goes

**68000 (A500 machine, 142 101 cycles per field, 9–10 fields per frame):**

| bucket | share of all cycles |
|---|---:|
| 3D view `+060A8` (inclusive) | 42.0 % |
| sky/ground, horizon, attitude ball `+077B8` | 8.5 % |
| cockpit `+0AA4C` | 8.6 % |
| swap `+04496` (MakeScreen, RethinkDisplay; mostly ROM) | 4.5 % |
| vertex rotation `+05EA4`, axis tables `+05CBE` | 4.3 % |
| moving map `+0468C` | 1.4 % |
| simulation tick (outside rendering) | ≈1–2 % |
| supervisor: level-3 interrupts (BLIT ≈10–11 %, VERTB ≈9 %) | 19.7 % |
| exec STOP idle (the WaitTOF in RethinkDisplay) | 4.6 % |

Across these buckets, about 21 % of all cycles are the CPU spinning in the BBUSY wait loops. The
geometry work (transform, projection, culling, clipping) is about 19 %.

The hottest instructions are the BBUSY polls themselves:
- `+08626`/`+0862C` in the line drawer: 7.4 %
- `+09242`/`+09248` in the band clear: 5.5 %

**68020 to 68060 (aprof, % of all clock units):**

| machine | fps | BBUSY spin | level-3 interrupts | swap incl. VBL wait | geometry (self) | idle |
|---|---:|---:|---:|---:|---:|---:|
| 68EC020/14 | 15.1 | 43.6 % | 17.6 % | 15.0 % | 10.6 % | 10.2 % |
| 68030/50 | 10.0 | 45.1 % | 16.7 % | 12.1 % | 9.1 % | 9.5 % |
| 68040/25 | 15.2 | 68.9 % | 5.3 % | 11.1 % | 1.5 % | 10.1 % |
| 68060/50 | 15.2 | 68.9 % | 5.3 % | 11.1 % | 1.5 % | 10.1 % |

**From the 68020 on, the game is limited by the blitter.**
- The 68040/25 and 68060/50 produce identical profiles, frame for frame: CPU speed no longer
  changes anything.
- On the 68060 a frame, about 3.3 fields (66 ms), splits into:

  | part | routine | share | what dominates |
  |---|---|---:|---|
  | 3D view | `+060A8` | 34.5 % | polygon blits `+08B6C` 18.7 %, line blits `+08538` 11.7 % |
  | background | `+077B8` | 27.0 % | band clear `+0921C` 22 % |
  | cockpit | `+0AA4C` | 21.3 % | re-blitting the cockpit frame over the view, `+0AA80`, 11.5 % |
  | swap | `+04496` | 10.8 % | almost all of it the wait for the next vertical blank |

  Nearly all of the first three is BBUSY spinning.
- Blitter busy time is about 51 ms per frame on the A500 and about 59 ms per frame on the
  68EC020. That caps this scene at about 15–16 fps on any CPU, as long as the blits stay as they
  are.

**Per-blit interrupts do nothing useful.**
- Graphics.library leaves INTENA.BLIT enabled, so every game blit ends in a level-3 interrupt.
  That is about 28–57 per field.
- Each one goes through exec's dispatcher (`$FC0D14`) and the graphics blitter handler
  (`$FC6DFA`), which finds no QBlit queue, and exits through KickEmu.
- That costs about 520 cycles per blit on the 68000. It lands exactly between two blits, while the
  CPU waits to start the next, so it lengthens the blitter's critical path on every CPU.

**The swap is expensive.**
- MakeScreen + RethinkDisplay rebuild the copper lists every frame: about 8 ms per frame on the
  68000.
- RethinkDisplay then waits for the next vertical blank, so drawing never overlaps the wait.
- The swap also spins until the game's screen is in front (`+00B86`), and copies an unchanged
  palette.

### 1.6 Hazards on faster CPUs

These are the original game's hazards. B1/B2 now fix the waits and pixel
ordering; B3's data/code audit is in [CACHE_AUDIT.md](CACHE_AUDIT.md).

- **BBUSY read too early.** Every BBUSY wait reads DMACONR once, one to three instructions after
  writing BLTSIZE: `+02D84`, `+02EFA`, `+030C6`, `+0319A`, `+031E6`, `+08626`, `+088D8`,
  `+08BD6`, `+08D3E`, `+08D7A`, `+09198`, `+09242`, `+092F6`, `+0933C`.
  - On a 68020 or faster the first read can see BBUSY still clear. The next blit's registers, or
    the CPU's mask writes in `+08B6C`, can then hit a blit that is still running.
  - Kickstart reads DMACONR twice for this reason.
  - This was inferred from the code; no corruption has been observed yet.
- **Pixel writes without a wait.** `+0828A` (pixel plot) read-modify-writes chip bitplanes without
  waiting for the blitter.
- **Code, tables and caches.** Tables and vertex buffers live inside the code hunk (for example
  `+06ACA`–`+07592`, `+08D88`). They are written as data only, and no self-modifying code was
  found. B3 confirms that the writable islands are data, not instructions;
  chip DMA memory is non-cacheable and fast CPU-only data may use copyback.

## Part 2: plan

The order follows the goal. B makes fast CPUs safe. C fixes game speed: this is the change
that makes fast CPUs play correctly. D and E raise the frame rate, which on 68020+ means less
blitter work. Each step is one commit. After each, measure with the instruments of §1.1 and
compare state as described in A4, before going on.

### A. Measurement base

**Status: complete (A1–A5).** The source rebuild and VERIFY-only fixed-seed,
completed-frame log and tick-checkpoint instruments are validated for version 0658.
CUSTOM2=0 applies no diagnostic patches; a nonzero CUSTOM2 selects the seed.
CUSTOM3=1 additionally selects an authored combat starting position, with three
ground targets and an existing enemy helicopter initially in view. Normal builds
contain none of these instruments and are byte-identical to the initial rebuild.
The shipped/rebuilt difference is fully accounted for: 160 bytes in the shared
SDK prefix, 72 bytes of date strings, and twelve validated symbol relocations in
an otherwise identical 780-byte game-specific tail.

The five-CPU take-off matrix and the 68000/060 hover and combat windows pass,
each over exactly 500 game VBLs. Two independent boots have byte-identical entire
8 MiB fast-RAM snapshots at ticks 100–102; neighboring ticks differ, including
player state with the tick counter excluded. Seed 1 selects the same mission on
all five CPUs and with extra menu delay; seed 2 changes it. The 8192-row bounded
swap log passes 128 register/CCR/overflow cases and agrees with continuous aprof
swap counts on 020+. Barto's omitted fields are explicitly accounted for.

Build and acceptance commands, fixture details, hashes and raw evidence live in
`tmp/dev/docs/measurement-a.md` and `tmp/dev/tmp/a-final/` (ignored harness).
`tools/compare_states.py` supplies A4's regression gate; matching simulation state
across CPUs remains an acceptance requirement for the future C changes. A itself
introduced no B–G performance or game-time changes.

Measurement correction: the original multi-capture route advanced 524 VBLs, not
500, because each emulator capture includes an unrecorded lead-in field. New
measurements assert 500 actual game VBLs and use the continuous completed-swap
log for fps and pacing. Barto percentages describe its recorded sample; aprof
covers the full window on 68020+. With seed 1, completed fps are 5.1 / 10.5 / 10.9 /
15.3 / 15.3 on the 68000 / 020 / 030 / 040 / 060 configurations above. The historical
uncontrolled numbers in Part 1 are motivation, not the controlled baseline.

| Window | 68000 fps / ticks/s | 68060 fps / ticks/s | Frame interval (VBLs), 68000 / 060 |
|---|---:|---:|---:|
| Take-off | 5.1 / 2.5 | 15.3 / 7.6 | 9–10 / 3–4 |
| Hover | 5.5 / 2.8 | 16.7 / 8.4 | 9–10 / 3 |
| Ground attack | 5.3 / 2.7 | 16.6 / 8.3 | 7–13 / 2–4 |

These are the instrumented emulator baseline, not hardware performance claims.
The combat window averages 19.3 full shapes/frame on the 060 versus 14.0 in
take-off. Its AI remains active, so the helicopter can leave the view.

- **A1. Rebuild the slave from source.**
  - A1a. Build `GunshipHD.s` with vasm against the current WHDLoad includes, using kick13.s.
  - A1b. Compare the result with the shipped v1.2 `Gunship.slave`, and explain every difference
    (date string, include versions).
  - A1c. Keep the build output out of the tracked tree.
- **A2. VERIFY build with a fixed mission.**
  - A2a. Find the random number generator and its seeding. The mission choice depends on input
    timing (the ops order changes with the route's click timing).
  - A2b. Add a VERIFY-only CUSTOM option that fixes the seed, so every CPU flies the same
    mission and scene.
  - A2c. Re-measure the §1.5 matrix with it.
- **A3. Benchmark windows.**
  - A3a. Keep the take-off window of §1.1.
  - A3b. Add a busier window: ground attack with several targets in view, and an enemy
    helicopter.
  - A3c. Add a hover window with little on-screen change.
  - A3d. Record fps, ticks per second and per-frame field timestamps, so pacing jitter can be
    measured as well as the average.
- **A4. State comparison.**
  - A4a. Snapshot the simulation state (`D3B88`… player block, object tables, the clocks of
    §1.3) when the tick loop `+0563A` completes a tick.
  - A4b. Check that two boots compare equal and that different ticks do not.
  - A4c. Use the comparison for every change in C: matched ticks must compare equal across
    CPUs once C is in.
- **A5. Frame log.**
  - A5a. Add a VERIFY-only log of (VBL counter, tick counter) at each swap, kept in slave memory.
  - A5b. Read the log with the read-only debugger.
  - A5c. This works on the 68030 and up, where Barto traces are empty, and it measures pacing.

### B. Correctness on fast CPUs

**Status: complete (B1–B4).**

**B1/B2 complete.** `blitter.i` validates all 14 `BTST/BNE` loops (12 using
a0, one a1, one a6) and the unique pixel-write helper call before modifying the
loaded game. It replaces each loop with `JSR/NOP` and wraps the pixel helper
with the same double-read wait. Registers and the original wait's CCR effects
are preserved. This is unconditional on all three recognised gamemule paths.
Instruction signatures avoid assuming a common offset delta between releases.
Any missing, additional or malformed match aborts before patching.

PAL 0658 and NTSC 1489 binaries pass assembled dispatcher tests; malformed
layouts are rejected without partial writes. Delayed-BBUSY and all 32 CCR
combinations pass. PAL flight smoke checks pass on 68000 and 68060. The German
dispatch path is exercised with relocated fixtures, but an original German
binary has not yet been tested; its runtime signature checks remain mandatory.

**B3 complete.** [CACHE_AUDIT.md](CACHE_AUDIT.md) inventories all writable hunk-0
islands, including indirect stores. The audit accounts for 267 direct write
sites at 138 destinations and finds no overlap with executable instructions.
The existing `CACHE` policy is appropriate: non-cacheable chip/base memory,
copyback fast/slave memory, and a flush after LoadSeg callbacks finish patching.
No additional runtime flush or data relocation is needed. VERIFY records the
load-time cache policy and exposes a completed-swap checkpoint with the tick
in a CPU register, avoiding stale debugger reads of copyback data.

**B4 complete.** All 21 completed-frame captures match byte-for-byte across
40,000 displayed bitplane bytes and the 64-byte palette: nine A2 cycle-exact
68020/68040/68060 samples at ticks 100/110/120, plus twelve cache-functional
samples at ticks 300/310/320 (68020, full-MMU 68040/68060, and 68040 NOCACHE).
The latter use CPU-observed ticks and buffer selection; physical RAM can lag
copyback data. Cache-on policy is `0x3b3d`; the NOCACHE control reports zero.
The full-MMU cache checks use immediate blits because the asynchronous-blitter
emulator configuration reproduces cockpit corruption with both the pre-B slave
and NOCACHE. They validate cache correctness, not blitter timing or performance;
timing coverage comes from the cycle-exact runs and delayed-BBUSY tests.

The 180 assembled blitter cases and 128 frame-hook cases pass, as does a
SetCPU scratch-register preservation test. PAL 68000/68060 flight and 68060
combat smoke checks pass. NTSC 68060 reaches flight with all 14 waits patched,
using a live-pilot roster only in its disposable runtime copy. All 226 original
PAL, installer and NTSC files remain unchanged. Evidence and reproducible commands
are retained in the ignored harness (`docs/measurement-b.md`,
`tmp/b/acceptance.json`). Original German and real-hardware coverage remain
release limitations, not implied by these emulator checks.

- **B1. Safe blitter waits.**
  - B1a. Replace the 14 BBUSY loops of §1.6 with a slave routine that does a dummy DMACONR read,
    then the BBUSY loop. Patch each with `PL_PS`/`PL_P`, keeping the loop's register use.
  - B1b. Add a wait to `+0828A` before its read-modify-write.
- **B2. Make B1 the default.** Apply B1 for all CPUs, since the cost on the 68000 is a few cycles
  per blit. Patch the other two supported versions (`gamemule_1489`, `gamemule_german`) at their
  matching offsets.
- **B3. Cache audit.**
  - B3a. List all writes into hunk 0, and confirm none of them is ever executed.
  - B3b. Confirm the slave's `CACHE` setting suits the 68040/68060 with copyback.
  - B3c. Fix with flushes or by moving data only if the audit finds a problem.
- **B4. Validate.** With the A2 seed, run the 68040/68060 and compare screenshots at matched
  ticks with the 68020: the picture must be identical.

### C. Game time independent of frame rate

This follows AmigaXDev `docs/playbooks/fixed-time-simulation.md` and
`simulation-and-presentation.md`.

**Status: in progress; C1 awaits the user's cadence choice.** The C4d
baseline pricing gate supports the proposed original-A500 cadence. In the
retained A2 68000 traces, contiguous intervals from the return of rendering
(`+05836`) to the next render call (`+05830`) cost:

| Window | Complete sampled intervals | Mean cycles | Maximum cycles | Mean / maximum fields |
|---|---:|---:|---:|---:|
| Take-off | 25 | 34,099 | 37,426 | 0.240 / 0.263 |
| Hover | 28 | 33,639 | 36,244 | 0.237 / 0.255 |
| Ground attack | 25 | 41,431 | 109,046 | 0.292 / 0.767 |

These intervals span the loop boundary and cover one native tick's work outside
`+04288`, including interrupt/OS cycles that occur inside the interval. They do
not cross the omitted fields between trace captures. At 142,101 cycles per PAL
field, their mean cost is 1.32–1.62% of an 18-field budget. This is a feasibility
measurement of the existing loop, not a measurement of a finished scheduler:
moving effect updates out of drawing, preserving input history and making
snapshots will add work. Sustained catch-up, pause recovery and the final 68000
cost remain to be validated. The ignored harness retains the reproducible
analysis in `tools/price_ticks_c.py` and `tmp/c/tick-cost.json`.

Two cadence dependencies need particular care during implementation.
`+09B9A` allocates an effect slot and calls the gameplay RNG three times, so
calling it per displayed frame changes later simulation state. `+0BE5A`
advances those effect slots using the six VBL-decremented bytes at `+0C724`;
these bytes are effect-animation timers, not six warning-lamp timers as the
initial time-model notes suggested. The gauge routine `+0ADB6` keeps separate
drawn heights for the two buffers; elapsed-time slew and per-buffer repaint
must be treated separately.

- **C1. Choose the tick rate. This is the user's decision.**
  - (a) A fixed rate equal to the original A500 pace, about 2.7 ticks/s (one tick per 18 fields).
    The flight model and every per-tick constant stay unchanged, and rendering interpolates
    between ticks. This is the recommendation for a first version.
  - (b) A user-selectable rate (CUSTOM option), for example 18 fields per tick plus faster
    settings. That keeps the "fast" feel of today's accelerated machines as an option.
  - (c) A higher simulation rate with rescaled constants. This is plan G, not part of C.
- **C2. Tick scheduler.**
  - C2a. Replace the fixed render count in `+04288` with elapsed time: a tick becomes due when
    the VBL counter `h2:001C` has advanced N fields since the previous tick.
  - C2b. Between ticks, render as many frames as time allows.
  - C2c. Keep an owed-fields accumulator so speed stays exact over time.
  - C2d. Count only fields in which the game screen is active, as the VBL server already does.
- **C3. Interpolation by elapsed time.**
  - C3a. The interpolation code at `+0433C`–`+043E2` already blends 27 camera/effect words and
    the instrument values with `frac = acc / period`.
  - C3b. Feed it `frac = fields since tick / N` instead, clamped to [0, 1].
  - C3c. Render at least one frame per tick.
- **C4. Catch-up on slow machines.**
  - C4a. When a frame takes longer than N fields (the A500 in heavy scenes), run overdue ticks
    back to back without rendering, up to a bound.
  - C4b. Make the bound a fixed number, and drop or rebase the excess time.
  - C4c. Report that excess time, so pauses and disk loads add no backlog.
  - C4d. Price this first. On the A500 one tick currently costs one or two frames of work.
    Measure the tick-only cost (`+0563A` minus `+04288`) to decide whether option C1a is
    sustainable on the 68000. If it is not, keep the original behaviour there as an option.
- **C5. Interpolate everything that moves.**
  - C5a. Only the camera, the instruments and six effect objects are interpolated today.
  - C5b. List the world objects that move per tick: enemy vehicles and helicopters, missiles,
    rockets and the "special object" at `62(a5)`.
  - C5c. Snapshot their previous and current positions at tick completion, and blend them in the
    renderer.
  - C5d. At 2.7 ticks/s, any object left out visibly jumps two or three times per second.
- **C6. Per-frame state to per-tick or per-field.**
  - C6a. Bar gauges `+0ADB6`: currently 1 pixel per frame. Make them per field, keeping the
    pace they had at about 5 fps.
  - C6b. Effect spawning `+09B9A`: one per frame while `D42F7` is set. Make it per tick or per
    field.
  - C6c. Effect animation `+0BE5A`: check it, and make it per tick or per field.
  - C6d. Map re-check every 8 frames `+0468C`: make it per field.
  - C6e. Key code 12 (`+04EF2`, `D1548` toggle): redefine it as the interpolation on/off switch,
    with no effect on game speed, or retire it.
  - C6f. Leave the buffer-indexed dirty counters (2 frames = both buffers) as they are.
- **C7. Input.** Controls are read once per tick, as now. Keep the joystick/mouse accumulation in
  the VBL server, and make sure that catch-up ticks (C4) do not reuse the same stick deflection
  more than once.
- **C8. Validate.**
  - C8a. Matched-tick state equality between the 68000, 68020 and 68060, with the A2 seed and the
    same input on the same ticks.
  - C8b. Equal-elapsed-fields check: the same number of ticks per 500 fields on every CPU.
  - C8c. Durations in play: fuel, mission clock, weapon reload, lamp blink.
- **C9. Option.** A CUSTOM bit that restores the original coupling, for comparison and for users
  who prefer it.

### D. Remove fixed overheads

- **D1. Blitter interrupt off during flight.**
  - D1a. After OwnBlitter (`+0867C`), save INTENA and clear BLIT. Restore it before DisownBlitter
    (`+0868C`).
  - D1b. Check that nothing queues QBlit work during flight.
  - D1c. Expected gain: most of the level-3 time, which is 5 % (68040/060) to 17 % (68020) of all
    time and includes the one VERTB per field. On top of that it removes about 520 cycles of
    blitter idle between consecutive blits.
- **D2. Cheap buffer swap.**
  - D2a. Replace MakeScreen + RethinkDisplay in `+00B7C`. Build the screen's copper list once,
    then exchange the bitplane pointers for the two buffers, by patching the BPLxPT moves or by
    using two prebuilt copper lists.
  - D2b. Make the exchange in the game's VBL server, so the change happens at a vertical blank.
  - D2c. Keep the palette pokes that `+00AB8` locates (flash effects).
  - D2d. Drop the palette copy that changes nothing.
  - D2e. Keep the front-screen check, but stop spinning on it.
- **D3. Don't wait for the vertical blank.**
  - D3a. With D2, the task requests the swap and continues.
  - D3b. Before drawing into a buffer it waits only until that buffer is no longer displayed.
- **D4. Triple buffering.**
  - D4a. Add a third 40 KB chip bitmap where chip RAM allows: always on 2 MB chip machines, and
    optional on 512 KB.
  - D4b. The CPU and blitter then never wait for the display, and frame times stop rounding up
    to whole fields.
- **D5. Small fixes.**
  - D5a. Remove the redundant final wait at `+08D7A`.
  - D5b. Clear only the span-table rows of the previous polygon box in `+08818`, instead of all
    200.
  - D5c. Measure BLTPRI (blitter priority) during flight. The CPU rarely needs the chip bus when
    code and data are in fast RAM.

### E. Cut blitter work (the ceiling from the 68020 on)

- **E1. CPU renderer for the 3D view.** This is the main lever for fps on fast CPUs.
  - E1a. Draw the 320×90 view, 4 planes plus plane 4 where needed, into a fast-RAM planar buffer
    with the CPU:
    - Bresenham lines that set all colour bits in one pass, instead of one blit per plane,
    - direct span fills for polygons, with no mask plane,
    - `movem` fills for the sky/ground bands.
  - E1b. Copy the finished view into the chip back buffer once per frame: about 14–18 KB, a few
    ms.
  - E1c. Select it when the CPU is a 68020 or better and fast RAM exists, and keep the blitter
    path for the 68000.
  - E1d. The result must be pixel-identical to the blitter path at matched ticks (A4/B4).
- **E2. Cockpit overlay.**
  - E2a. `+0AA80` re-blits three cockpit-frame pieces over the view every frame, because the view
    is drawn underneath them: the top strip, the right strip and the attitude-ball bezel.
  - E2b. With E1, clip the view's copy and fill to the visible window shape (a mask from bitmap 3,
    plane 4) and drop those restore blits. Without E1, clip the band fills to the window
    rectangle.
- **E3. Remaining cockpit blits.**
  - E3a. Text (`+02F44`), needles (`+0AD30`), scope (`+0B740`) and tapes (`+0AB3C`) are about 7 %
    on the 68060.
  - E3b. Draw them with the CPU into the same fast-RAM staging, or skip them when their value has
    not changed.
- **E4. Overlap what stays on the blitter.**
  - E4a. For blits that remain (map, cockpit art, the 68000 path), queue them and start the next
    one from a game-owned BLIT interrupt, instead of spinning.
  - E4b. Measure first: on the 68000 the CPU work is about as long as the blitter work, so overlap
    could hide most of the 21 % spin.
- **E5. Expected outcome.**
  - E5a. With D and E, the work left on a 68030 or faster is mostly geometry: 1.5 % of today's
    frame on the 68060, plus the copy.
  - E5b. That should reach the 25 fps (2-field) level and, with triple buffering, beyond.
  - E5c. Measure it with A3/A5 rather than assuming it.

### F. Release

- **F1. Options.** Use CUSTOM bits for:
  - original timing (C9),
  - the tick rate (C1b),
  - the renderer choice (E1c),
  - triple buffering (D4).
  
  Defaults: new timing, with the renderer chosen by CPU.
- **F2. All versions.** Apply each patch to every supported `gamemule`/`titlmule`/`scrnmule`
  version at its own offsets. Where a version cannot be tested, say so in the ReadMe.
- **F3. ReadMe and slave version.** Bump the version, add a history entry, and document the
  options.
- **F4. Final check.** Run the full matrix (68000, 68020, 68030, 68040, 68060) on all windows of
  A3: fps, pacing jitter, ticks per second and state equality. Also play through a full mission
  on the 68000 and the 68060. Resolve or independently validate the full-MMU
  asynchronous-blitter emulator limitation documented under B4. The reported
  68060 T-74 copy-protection graphics issue remains deferred at the user’s request.

### G. Optional: a higher simulation rate

Only after C is done, and only if the 2.7 Hz control response feels too slow at 25–50 fps.
This means raising the tick rate and rescaling every per-tick quantity:
- G1. Classify each quantity as a rate, an acceleration, a distance or a countdown, as Stunt Car
  Racer did in the playbook.
- G2. Audit the flight model, AI, weapons, fuel and timers.
- G3. Validate behaviour in play, not only the arithmetic.

This is large and risky. It is not needed for smoothness, because interpolation provides
smoothness at the original tick rate.
