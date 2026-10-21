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
are preserved. The master CUSTOM1 **Enhanced framerate** option now gates
these patches on all three recognised gamemule paths.
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
- **B2. Apply B1 for every CPU when Enhanced framerate is enabled.** The cost on the 68000 is a few cycles
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
`simulation-and-presentation.md`. The design is the hybrid used in Wing Commander, where
the world kept its intended 10 Hz and the player's own motion became responsive (that
project's `docs/timing-design.md`, design D, and its phase-9 gate in `docs/internals.md`).

**Status: design selected; production timing unchanged, native input diagnostics tested.**

Implementation checkpoint: standalone clock/history cores are committed and
tested, including instruction-boundary producer interruption. Diagnostic native
input producers now capture real fields on 68000/020/060, and a dual-reader
queue retains accepted keyboard commands through their field cutoffs. The
foreground coordinator now enforces field/player/world ordering and bounded
batches in assembled-code tests. A standalone bridge now binds each delivered
field to a combined player candidate and acknowledges it only after motion
commits, exposing the native height/contact boundary for deferred ground
effects. Bounded command drains now bind both retained readers to the
scheduler phase and delivered cutoff in standalone integration tests.
Its native main-loop installation, remaining command callbacks/lifecycle
policies and complete player/world hand-off are still pending,
so C2/C3 are not complete. A guarded single-frame handoff now publishes the
current pose and calls native drawing once; it defers fields arriving during
drawing to the next batch (forty assembled handoff cases). The experimental native
flight-loop caller now uses it. A foreground loop owner now composes bounded batches,
draws, retained commands, modal continuation, excess-time rebase and flight
exit, with PAL/NTSC comparisons against explicit dispatch. Its native entry
hook and Exec interrupt-exclusion adapters are now installed in experimental
TIMING_RUNTIME builds only. The first 68020 live run exposed stale geometry coordinate ranges copied
before flight initialization: the private check falsely ended flight at
17 fields while the committed raster flag was clear. Refreshing the native
coordinate table before rebuilding each committed scene fixes the captured
model traversal and plane results. The 96-scene native comparison now also
starts with stale private table data (176 signature rejections still pass).
The corrected headless 68020 run reached 1,060 fields and 63 world ticks,
with no lost/discarded history, scheduler fault or unexpected flight exit
(`tmp/dev/tmp/c/live-loop-020-refresh`). This is initial loop activation
evidence, not full C9 gameplay/CPU acceptance. A corresponding 68060 run
reached 1,139 fields and 68 world ticks without history loss or faults.
A separate 68000 address error in the private instrument height word store
is fixed with byte stores; 65,536 native comparisons cover both buffer
alignments. Its live loop now advances, but discarded 148 fields through
bounded excess recovery in the sampled run: C9 real-time rate still fails
on that configuration. C8 catch-up now also skips a render when fields
arrived while draining the previous snapshot. In the matched 68000 profile
route this removes 148 discarded fields and raises completed worlds from
42 to 52, but the backlog still grows (54 fields at the end); sustained
rate acceptance remains open. Grouped longword copies in the player
transactions further reduce the same run's final backlog to 11 fields,
with 55 completed world ticks and no lost/discarded input; exact tails,
rollback and 360 native boundary comparisons pass. A validated zero-motion fraction fast path then sustains 188 worlds over
62.68 emulated seconds (2.99936 Hz) in the longer PAL 68000 idle run, with
no lost/discarded history and sampled backlog 4..16 fields. Heavy-scene,
NTSC, display latency and cross-CPU state gates remain open.
Subsequent NTSC 68020 idle and 68060 takeoff runs sustain approximately
3 Hz without time loss, but NTSC 68000 runs at 2.574 Hz and discards
371 fields over 50.5 seconds. Critically, the PAL catch-up/copy/zero-motion
100-field profiles contain zero completed renders: catching up can starve
drawing despite near-3-Hz simulation. C8/C9 are not accepted; bounded
render progress and measured display latency must accompany rate checks.
The four-world catch-up allowance is now shared across snapshots, fixing
unbounded renewal: the 68000 profile again records swaps, but the sampled
world rate is 2.558 Hz with explicit time discards. The 68020 records fifteen
swaps in two PAL seconds and preserves near-3-Hz takeoff timing without
lost/discarded input. The starvation fix is not a responsiveness acceptance. Native world opening and the complete periodic
reserve/housekeeping/flight-end tail are now extracted and tested separately;
the weapon block also has a private-input extraction with native launch
comparisons. Active-actor sequences and scheduler-bound guided release are
now tested, and damage has a deadline-input extraction with native comparisons.
Scripts now have a nonblocking extraction and explicit boundary before the
native modal interpreter. A post-motion coordinator now composes weapons,
damage, scripts and the periodic tail with once-only modal continuation,
tested against the native sequence. Remaining field/world ownership, full
player/world composition and lifecycle continuation remain pending.
A standalone private scene geometry path now rebuilds committed scene inputs
and evaluates the native flight-end plane flag without renderer writes; its
world-tick ownership and collision trajectory acceptance remain pending.
The superseded coupled-substep path fails the moving-geometry gate: 44 ten-second trajectories produce
82 differing hit decisions in 1,320 world-boundary comparisons (54 native hits
missed by the field path, 28 converse differences). Native reference records
were independently verified against original instructions. C4e/C5b remain
unaccepted; this is not just a pending test or a renderer-isolation issue.
The user has now selected preserving native motion at world-tick boundaries
while retaining responsive field-rate input and motion. An interval-anchored
prototype matches all 1,320 reference records and collision probes in that
same fixture. It also responds fractionally to a pulse wholly between ticks.
The replacement now has assembled distribution, a transactional interval
owner, scheduled ground publication, full-strength disturbance correction
and fractional camera reconstruction. Held-input ground/disturbance endpoints
match native previews, and the combined native-world fixture is batch-invariant
over 1,440 fields. Disturbance generation now has a retained per-deadline cache
for recovery without duplicate RNG draws. These remain standalone/harness
components, not the installed replacement integrator. Changing-input contact
and map-edge behavior, lifecycle integration, other-object prediction,
instrument slew, CPU cost/cross-CPU tests and live validation still block C.
Core lifecycle suspension/rebase now coordinates the clock, both queues,
scheduler and endpoint history, with pending-work guards and retained
diagnostics. A standalone modal continuation now runs the native interpreter
with sampling off, finishes the pending world tail and acknowledges it once.
The runtime lifecycle adapter now resets helper metadata and coordinates
input ownership; production producer exclusion and native hook installation
remain pending.
The standalone `timing-flight-consumer.i` now owns the assembled foreground
ordering for each delivered field, including bounded command resumes,
player/world hand-off, ground-event publication and modal returns. Its
sequence matches the independently driven combined fixture; native loop
installation remains pending.
`timing-runtime-batch.i` now drives bounded scheduler snapshots and the field
consumer together, including command-budget resumes and explicit lifecycle,
modal, flight-end, fault and excess-time returns. It does not silently start
a fresh batch after a stop. Native flight-loop and render handoff installation
remain pending.
The native lifecycle/display command adapter now preserves ordinary and
nonlocal exit stack behavior, including Escape while paused. It retires
the old key-12 speed toggle in the enhanced path. A paused-queue completion
marker now lets both readers acknowledge an executed boundary without
repeating it. Runtime suspension/execution now retains the boundary, disables
private sampling, runs native UI once and records marking failures without
replay. Its native VBL gameplay timers stay frozen while UI owns keyboard
input. A completion entry now finishes the retained field/world while
sampling remains excluded, handles subsequent keyboard/script boundaries,
and separately accounts native exits that cancel the delivered field.
Fresh rebase and first-field acceptance are tested; native-loop activation
and live lifecycle validation remain pending.
`timing-core.i` now supplies a shared include order, and `timing-runtime.i`
prepares a single paused arena with all consumer/native-copy bindings.
Loader-chain discovery no longer requires debugger markers. Production
activation remains pending.
An experimental `TIMING_RUNTIME` slave build now allocates/prepares that arena
at the supported module's LoadSeg callback, behind CUSTOM1, and releases it
after the main program returns. Existing LoadSeg cache flushing covers setup.
It leaves sampling paused; runtime start and native flight hooks remain open.
Experimental runtime builds now install arena-backed field/mouse/command/fire
capture hooks with separate producer and consumer records. Sampling remains
paused until foreground ownership is installed. The diagnostic rearm key is
absent from this runtime path, and duplicate diagnostic patching is suppressed.
The accepted-key hook can now retire the appended native FIFO slot after
successful private retention under explicit runtime ownership. Ownership still
defaults off. Tested runtime activation/suspension/modal adapters now establish
fresh epochs, account for discarded native FIFO keys and hand input ownership
back and forth. Native flight/menu entry points must still call them.
Experimental runtime builds also switch the three native VBL countdown
stores and guidance call by that ownership flag. Runtime ownership suppresses
their native state updates so the field consumer can replay them once.
Ownership defaults off. Guidance now retains the latest native request for
each of its two hardware sprites; a tested presentation entry applies those
requests without advancing guidance state. The render handoff and cosmetic
timer snapshots remain pending before gameplay activation.
The experimental runtime also suppresses the renderer's effect constructor
under runtime ownership or a retained UI boundary. The recurring hit effect
is now explicitly scheduled once per world deadline, alongside the existing
damage-triggered effect calls. Native ownership retains the original
constructor behavior. Effect countdowns and animation now replay once per
consumed field, before world work; their native VBL/render writes are excluded
under runtime ownership and retained UI boundaries. All 65,536 frame/timer
byte pairs match native arithmetic, and 960 PAL/NTSC fields agree across
batch sizes, including slot state and RNG. The slot-lifetime counterexample
now releases on the same field with fast, slow or disabled drawing. Other
renderer state writes and production activation remain open. Combined
`TIMING_INPUT`/`TIMING_RUNTIME` builds use the runtime input arena and VERIFY
output, omitting the unused standalone diagnostic recorder and its buffer.
The initial C4a/C4b inventory is
in `PLAYER_STATE_INVENTORY.md`; it includes camera/instrument destinations and
the HUD's authoritative pitch clamp. A standalone deterministic field-rate
stick-attitude step is tested. A standalone continuous-motion coordinator
now connects scaled heading, flight rates, displacement and wind in native
order; its control/world hand-off and production installation remain pending.
A combined continuous player entry point now applies the authoritative
pitch clamp and decoded stick attitude before that motion step, with
rollback across all components. Native input decoding, command ordering
and the world boundary remain caller responsibilities and are not yet
installed.
The initial coupled held-control measurement exposes changed response
equilibria: fractional exponential response continues inside the native
integer zero-increment range. Those stopping ranges are now retained for
flight-rate responses. A subsequent altitude-normalization fix removes
the delayed integer-height boundary that selected a different vertical
equilibrium. Combined whole-tick player/world comparisons now pass with
native motion RNG, ground effects, opening and post-motion world work,
including consecutive ticks. Moving-stick tests also exposed and corrected
a field-clamp change to the native held pitch endpoints (-14/+22), followed
by fractional-pitch hover/bank branch selection to avoid an unintended
90-degree track turn. A transactional continuous-player wrapper now retains
the native previous-control time horizon, removing most measured reversal
pitch drift. The ground-compatible split transaction now commits that
history with successful player motion and rejects stale history. The
scheduler now delivers that history through the split transaction, with
batch-invariance and before/after-publication fault tests. Deadline world
commands are also drained before player motion, matching native engine/mode
ordering. A combined scheduled fixture now runs guidance, delayed player
motion and the extracted native world path with identical state across
PAL/NTSC catch-up batch sizes (2,880 fields). World opening now has a
deadline guard that retains applied clock/cooldown state across a producer
fault and rejects retries. Three world-written VBL countdowns now replay
with guidance in native order per delivered field, with native arithmetic
and combined batch comparisons. Production adoption, remaining lifecycle
recovery and trajectory/collision acceptance remain. C4e is still not accepted: field-rate coupled
trajectory differences, moving controls and collision behavior still need
explicit bounds and validation before installation.
The camera/instrument builder is now extracted and native-equivalent in
standalone tests, with the pitch clamp separate from read-only presentation;
its native installation remains pending. A separate field-clocked bar-gauge
primitive now matches 2,000 native updates and 738 skipped-draw catch-ups.
It is bound to the experimental field consumer, lifecycle and CUSTOM1-gated
painter, with 800 PAL/NTSC fields invariant across batch sizes. Live gauge
validation is still pending. The cockpit audit confirms +0AB20 is a
two-buffer repaint count (C7e) and +0AD30 derives needle geometry directly
from current instruments; neither needs a field-rate countdown.
A read-only fractional camera adapter now exposes the first field's
attitude changes in camera angle words; whole-tick camera arithmetic is
preserved, while enhanced pitch removes the integer half-angle staircase.
Live input-to-screen latency remains unmeasured.
The runtime now publishes native single-frame scene/instrument inputs directly
from the latest player state and fractional camera, with no old render-count
loop. Native endpoint comparisons and write-range checks pass. Other objects
remain committed poses in this publisher; prediction and the actual
frame-render handoff still need integration.
An experimental committed-view raster extraction now collects candidates and
their native pixel samples before overlays, restoring native target state
after collection. Its CPU behavior matches the original drawing prefix over
48 views. A compiled guest probe also matches real blitter output, candidates
and sampled colors in 16 PAL views on each of the 68000, 68020 and 68060.
The isolated pass averages 71/32/22 ms on the PAL 68000/020/060 fixtures;
whole-game timing remains open. The experimental field consumer now invokes
visibility and native-equivalent target selection once per world deadline,
after committed player motion and before geometry/weapons. Field stamps reject
replay, and render hooks suppress collection/selection except inside that
world pass. Normal native ownership remains unchanged. Runtime activation and
presentation of the locked target in the latest rendered view remain open.
See `TIMING_DESIGN.md` for tested scope and remaining integration obligations.

**Design.** The game has two timing owners:

- **The world runs at exactly 3 ticks per second of real time** (C1). AI decisions,
  gameplay RNG, weapon launches, damage, collision results, the mission, effects, fuel and
  the Elapsed Time clock keep their native per-tick code. Decisions per second, random draws
  per second and every duration therefore stay as designed.
- **The player's own motion runs at field rate.** Controls are sampled every field. The
  helicopter's attitude, heading, speed and position are integrated every elapsed field with
  native tick's motion distributed across the interval, with its contribution
  recalculated from fresh controls every field (C4c/C4e). The camera and the
  instruments follow that state on every rendered frame. Input reaches the screen on the
  next rendered frame, not up to 333 ms later.
- **Other moving objects** keep their world-tick motion and are drawn with bounded
  renderer-only prediction (C6).

Native code still decides everything discrete. The user-selected handling
criterion also preserves native player endpoints with held input, rather
than accepting the different trajectories produced by finer physical
integration. Inputs that change between ticks must still affect motion
immediately; their additional response cannot also equal a native tick that
never sampled those inputs. C4e distinguishes those two cases.

Forward extrapolation alone was rejected: it smooths pictures while input and the player's
motion stay at 3 Hz. Raising the whole simulation rate (G) was rejected as the main route:
it changes how often discrete logic runs and needs every quantity rescaled.

**Measured basis.** The tick is cheap. In the retained A2 68000 traces, contiguous
intervals from the return of rendering (`+05836`) to the next render call (`+05830`) cost:

| Window | Complete sampled intervals | Mean cycles | Maximum cycles | Mean / maximum fields |
|---|---:|---:|---:|---:|
| Take-off | 25 | 34,099 | 37,426 | 0.240 / 0.263 |
| Hover | 28 | 33,639 | 36,244 | 0.237 / 0.255 |
| Ground attack | 25 | 41,431 | 109,046 | 0.292 / 0.767 |

These intervals span the loop boundary and cover one native tick's work outside
`+04288`, including interrupt/OS cycles that occur inside the interval. They do
not cross the omitted fields between trace captures. At 142,101 cycles per PAL
field, the mean cost is 1.4–1.7% of a 17-field tick (up to 1.8% of a 16-field
one). This measures the existing loop, not the finished scheduler: input history,
the field-rate player step and snapshots add work, priced in C4f. The ignored harness retains the analysis in
`tools/price_ticks_c.py` and `tmp/c/tick-cost.json`.

**Known cadence dependencies.**

- `+09B9A` allocates an effect slot and calls the gameplay RNG three times, so
  calling it per displayed frame changes later simulation state.
- `+0BE5A` advances those effect slots using the six VBL-decremented bytes at `+0C724`.
  These bytes are effect-animation timers, not warning-lamp timers as the initial
  time-model notes suggested. Animation completion writes the shared slot lifetime,
  which the world uses to release the allocation bit. A native-instruction fixture
  releases the same slot on world tick 4 versus 5 at different render cadences.
  Countdown and animation advancement therefore need ordered field ownership;
  leaving the animator in the render call is not presentation-only.
- The gauge routine `+0ADB6` keeps separate drawn heights for the two buffers. Elapsed-time
  slew and per-buffer repaint are now separated in the experimental runtime:
  private heights advance per consumed field, and the painter catches up its
  selected bitmap while restoring temporary targets. Live visuals remain unvalidated.
- Rendering produces a result the tick consumes: `+05C28` clears `D3958`, the shape-facing
  routine writes it at `+0691C`, and `+0583C` tests it after rendering and can set the
  player's flight-end state (C7).

- **C1. World clock: exactly 3 ticks per second.**
  - C1a. The criterion is that the in-game clock runs at the correct speed.
    The original Elapsed Time display divides the unsigned tick counter
    `D3B94` by 3 for seconds, then by 60 for minutes. Its conversion starts at
    `+023A4` / `+023CE` in PAL 0658 and `+02380` / `+023AA` in NTSC 1489.
    Executing the original conversion code passes 1,102 boundary cases per
    version, including minute/hour boundaries and the word counter's maximum.
    Evidence: ignored `tools/test_clock_c.py`, `tmp/c/clock-contract.json`.
    Native result-screen captures now show 01:04 after 192 real world ticks
    on PAL 68060 and NTSC 68020 (64.02/64.10 native-field seconds, no active
    time/input loss). A guest-only diagnostic exit requests the result screen
    without editing the tick count; this verifies clock UI, not natural landing.
  - C1b. Schedule 3 ticks per 50 PAL fields or 60 NTSC fields, carrying the fractional
    remainder. PAL deadlines therefore alternate 17/17/16 fields; NTSC uses
    20 fields. Use the measured display frequency, not the executable's region.
  - C1c. Keep native world constants and the display's conversion unchanged.
- **C2. Tick scheduler.**
  - C2a. Replace the fixed render count in `+04288` with elapsed time: add three
    clock units per active VBL and consume one display-frequency quantum per tick.
  - C2b. Between ticks, render as many frames as time allows; each render first consumes
    the elapsed fields' input history (C3) and player steps (C4).
  - C2c. Count only fields in which the game screen is active, as the VBL server already does.
- **C3. Field-stamped input history.**
  - C3a. Extend the VBL server's joystick/mouse read (`+01068`) and fire latch (`+04DC6`) to
    publish one record per field into a bounded ring: stick or mouse deltas, buttons, and
    the keyboard command position. A full ring keeps the unread records, counts the loss and
    forces a rebase.
  - C3b. The player path (C4) consumes every record once, in field order.
  - C3c. The world tick consumes the same interval once: button edges, held fire, keyboard
    commands and the controls that feed world decisions. It must not apply stick deflection
    to the player a second time.
  - C3d. Audit how the native tick turns the accumulated stick and mouse values into control
    targets before choosing what a record holds.
- **C4. Player motion at field rate.**
  - C4a. **Inventory** every player field the tick writes (the `a5` = `D3B88` record and the
    camera/state vector built at `+057E2`): position `0(a5)`/`2(a5)`, altitude `28(a5)`,
    heading and attitude `53..55(a5)`, the reserves depleted at `+0594C`/`+0597A`, speed,
    collective/throttle, and so on. For each one, record its units, every writer and reader,
    and its update order.
  - C4b. **Classify** each as continuous player motion (integrated per field) or world-owned
    (committed per tick: fuel, damage, weapons, flight-end and landing states, scripted
    motion).
  - C4c. **Preserve native endpoints:** the original rate/acceleration and r^h
    substeps changed coupled motion enough to fail C4e/C5b. Replace that
    approach with interval-anchored native motion contributions, recomputed
    with fresh controls each field. Distribute each contribution over the
    actual delivered interval: 17/17/16 PAL fields or 20 NTSC fields. Keep
    exact fractional shadow state across intervals; the native variables
    retain the integer part. Preserve saturation, wrap and native stage
    ordering. Command changes, impulses and ground transitions require
    explicit ownership/rebasing tests before this replacement is accepted.
  - C4d. Run the native flight arithmetic where possible, previewing it on saved state
    rather than reimplementing it. Wing Commander previews its native steering routines and
    restores their state afterwards.
  - C4e. **Equivalence gate:** one step with h = 1 must reproduce the native tick's player
    state bit-exactly. **User decision: preserve native motion at world-tick
    boundaries while retaining responsive field-rate input and motion.**
    With held input, each complete delivered interval must reproduce the
    native endpoint without accumulated drift, including displacement.
    Test within-interval changes separately: every field's input contributes
    to motion, including a press and release between world ticks. Do not
    force such additional input back to an endpoint that ignores it.
    The interval-anchored prototype passes the existing held/boundary-change
    trajectory fixture, but production assembly, commands/impulses, lifecycle
    and live responsiveness remain unaccepted.
  - C4f. Price the per-field step and the history on the 68000; it renders about 5 fps and
    consumes about 10 fields per render.
    The full-input motion cache is now integrated into the experimental
    runtime. Cached/uncached motion matches across 1,760 PAL/NTSC fields.
    The sampled 68000 engine-start/takeoff route now discards zero history
    records versus 136 with cache bypass, reaching 80 versus 71 completed
    worlds at producer field 1,366. Heavy-scene throughput and the remaining
    CPU/state matrix are still open (TIMING_DESIGN.md, runtime cache comparison).
  - C4g. Rebuild the camera/state vector (`+057E2`) and the instrument values from the
    player state on every render. Gauges advance per consumed field (old C6a).
    Native needles have no incremental slew: +0AD30 derives their endpoints
    directly from the latest instrument angles. Keep their per-buffer restore
    caches and +0AB20 repaint counts drawing-owned, as required by C7e.
  - C4h. The native tick skips the integration of already-integrated player quantities and
    reads the field-rate result. This is Wing Commander's world rotation hook, which
    excludes the ordinary player.
- **C5. Hand-off between the player and the world.**
  - C5a. At each world tick, the world (AI targeting, ranges, collisions, lock-on, landing
    and pad checks) reads the player's latest field-rate state as authoritative.
  - C5b. Ground and object collision of the player is evaluated on committed state at the
    world tick. Test that fast movement between ticks cannot pass through terrain or
    obstacles that the native 3 Hz check would have caught, or the reverse. Do not assume
    finer motion improves collision detection.
  - C5c. **Weapon launch latency: (a) selected by the user for now.** Launches happen at
    the next world tick, from the player pose at that tick, as in Wing Commander, where
    that is up to 100 ms; here it is up to 333 ms. Latch trigger edges and held fire per
    field (C3) so that no press is lost between ticks.

    Deferred alternative (b): timestamp the trigger field, commit the launch at the next
    world tick, and start the projectile from the trigger-field pose, advanced by the
    elapsed fraction. Show it from the trigger field as presentation only; ammunition,
    lock and damage remain world-tick events. It changes the native launch pose and time,
    so it needs its own validation. Revisit it only after (a) has been played.
  - C5d. Render-time aiming (gun sight, target box) may show the current view but must not
    commit a lock, target change or launch. A private native-equivalent selector
    now accepts explicit per-candidate pixel colors and changes only its own
    target snapshot. A private full-projection/collector path now matches
    native pre-overlay candidate state in 48 drawing-omitted views; filtering/capacity
    checks add 1,536 native comparisons. Committed-view raster/pixel acquisition
    now matches native output in compiled guest tests on 68000/020/060 (16 PAL
    views each, both palette modes). The isolated pass is priced at roughly
    21%/10%/7% of elapsed time at three calls per second on those setups.
    The experimental runtime now publishes selection once per world deadline
    and excludes native render collection/selection under enhanced ownership,
    including retained UI completion. A private current-view capture primitive
    now follows only the world-selected identity through native projection
    filters (1,024 comparisons); it preserves committed target state and avoids
    candidate-list saturation. The experimental renderer now captures that
    projection, borrows it for panel drawing and restores committed targeting.
    Actual native projection matches in 64 views; draw-stub tests verify stale
    suppression and restoration. Compiled guest panel comparisons now match
    all five real bitplanes in 16 PAL views each on 68000/020/060, including
    deliberately stale committed coordinates and missing targets. Whole-game
    visual checks, timing and native flight-loop activation remain open.
- **C6. Presentation of world objects.**
  - C6a. Enemy vehicles, helicopters, missiles, rockets and the special object at `62(a5)`
    keep their world-tick motion. Draw them predicted from the latest completed state, at
    most one tick ahead, using `current + (next - current) * frac` where the next native pose
    is derivable from native order and arithmetic. Never draw them one tick behind.
    The scripted index-5 steering/terrain/RNG dependencies are now inventoried;
    its CPU terrain query has a read-only sampler matching 1,571 native pixel
    classifications. A private scripted steering/motion preview now matches
    804 native next poses without RNG, damage or gameplay writes. Scripted
    translation now has a generation-certified runtime snapshot and bounded
    renderer-only publication (37 PAL/NTSC fixture views). Complete writer
    coverage and live raster/visual/cost checks remain open. Renderer-only
    heading now uses the same certified interval; three gated native load
    hooks preserve committed-raster reads (2,560 register/CCR comparisons).
    Compiled guest heading draws now match all five bitplanes in sixteen
    views each on 68000/020/060; a wrong-heading control detects the mismatch.
    Full forecast-to-raster and whole-game continuity/cost checks remain open.
    A separate private forecast now recomputes the
    native steering mode and countdown: 180 prefix-plus-body comparisons
    match, and 44 unresolved modal transitions reject without world writes.
  - C6b. Certify object identity at the native constructors, so that a reused slot doesn't
    inherit its previous occupant's trajectory. Derive each projectile's first presentation
    interval from its spawn and update order. The native six-slot audit proves
    release/reallocation can leave the same mask, and impacts morph a slot in
    place. Generations must cover allocator +0BEA8's three constructor callers,
    with separate eligibility/morph barriers. A CUSTOM1-gated allocator hook
    now stamps all three callers, preserves native flags and resets on lifecycle
    activation (1,536 native comparisons). Eligibility/morph handling, other
    object families and live hook validation remain open. The experimental
    renderer now certifies cached projectile poses against generations,
    exhaustion, eligibility and motion state; lifecycle activation reseeds it.
    The scripted index-5 object's common store now has a CUSTOM1-gated generation
    hook covering its known spawn/removal/motion paths and excluding private
    previews (1,344 native ABI comparisons). Its translation consumer now
    rejects changed generations, poses and metadata; complete writer coverage
    and live hook acceptance remain open.
  - C6c. Bound prediction at known impacts; snap at discontinuities. Never write predicted
    poses into world state or pass them to collision, damage or AI. A standalone
    private six-slot native preview now matches 1,200 steps and rejects release,
    type changes, expiry, decoy hits and uncertain terrain contacts without
    world writes. Decoy-contact rejection is now per slot: the native skipped
    lifetime decrement identifies contact without freezing unrelated actors
    (22 native contact fixtures retain 90 unrelated predictions).
    The experimental runtime now captures after world completion
    and publishes certified forward fractions into renderer-only scene inputs
    (600 PAL/NTSC fields, 288 publications, invariant across batch sizes).
    A separate field-stamped cache now covers guided first-release intervals
    without shifting unrelated actors (both native guided weapon types, PAL/NTSC,
    batch sizes 1/3/10). Other object families, live cost/visual acceptance and
    native flight activation remain open (see TIMING_DESIGN.md).
    Current live Hellfire (type $80) captures match 71 selected states on PAL
    68020/060 and expire at world 85. However, two of 64 candidate next poses
    per CPU fail unconditional equality at target-selector changes. Replaying
    only the next selector reproduces the native poses exactly. The endpoint
    differences are 36/3/6 coordinate units; visible retargeting continuity
    and dependency certification remain open, with the raw failure retained.
    Cached homing presentation now also records its selector dependency and
    rejects a prediction if that selector has already changed, without
    suppressing independent projectile modes. This does not resolve future
    retargeting or its visual continuity; both mismatches remain recorded.
    Native projection replay now measures a two-pixel horizontal endpoint
    correction at world 27 in both PAL 020/060 next-tick cameras; neither
    world-45 pose reaches pixel drawing. Scanout continuity
    and a bound across views/distances remain unverified.
    Completed-frame captures now verify the world-27→28 transition at
    (159,60)→(157,62) on both PAL CPUs, with 9/6 fields between completed
    020/060 frames. All 49 projected poses match native draw coordinates;
    this confirms a small reversal on this route, not general continuity.
  - C6d. **Ground vehicles move slowly; projectiles do not.** If a 333 ms prediction horizon
    shows visible errors for projectiles, move their free flight to field rate under C4's
    rules, keeping hits and damage on world ticks. Measure this before doing it.
    The recorded retarget endpoints now have a native-projection near-view
    stress test: synthetic cameras at 256/128 coordinate units produce
    36/~72-pixel horizontal corrections, versus ~2 pixels on the distant
    live route. This rejects using that distant route as general acceptance.
    Native motion extraction must preserve the near-target substep collision
    checks and next-tick selector dependency (inventory in TIMING_DESIGN.md);
    pre-selection captures now isolate both recorded retargets to candidate
    collection (target 2 leaves/reenters the list), rather than pixel samples.
    Native collector replay now identifies the altitude-derived range limit
    at +A4B0 as the exact gate in all four boundary captures; the next limit
    is already written by the preceding world weapons update. Forecasting
    collection with a provisional native player endpoint now matches ordered
    candidate identities in 27/27 captured intervals without gameplay writes
    (current camera: 26/27). Retained endpoint-owner/ground replay also
    matches all 27 lists; supplying recorded next-tick impulses reproduces
    all 27 cameras exactly, while zero future impulses leave nine camera
    differences. All 65 natively admitted impulse branches retain the same
    candidate identities on this tape (6,912 RNG-adapter checks); this does
    not alone certify visibility. Exhaustive visibility predicates now prove
    invariant homing selector bytes for worlds 27..46; worlds 20..26 remain
    ambiguous. A private zero/one-candidate helper is implemented and native-
    equivalent (2,048 cases). A selector-fed private actor entry now reproduces
    all next Hellfire poses in 44 admitted branches across worlds 27..46,
    including both original errors, without native writes. Neither helper is
    installed in presentation yet. Forecast profiling verifies 64% fewer
    player instructions with the existing exact cache; a new collection-only
    scene entry saves another 3% of collection work with identical full
    candidate blocks in 108 views. These are offline instruction counts,
    not live frame-rate acceptance. Read tracing also exposed live player
    map-cell/view reads; an opt-in private-player binding now removes those
    dependencies (48 poisoned-input scenes, six positive controls). Other
    shared model/limit dependencies still need certification. The observed
    1,215 shared hunk bytes are stable in 35 same-world completed-frame pairs
    on PAL 020/060. Fresh captures also verify all nine external input bytes
    and their full 256-byte record block across 35 pairs, with no sampled
    input/time loss. Remaining-interval forecasts and intermediate owner/
    player checkpoints now match in all 35 pairs. An exact read-only matcher
    passes those pairs and 8,890 byte-mutation rejections. A private 20-checkpoint
    tape now passes all 35 lookups, 840 context-byte rejections, capacity,
    partial-publication, retirement and field-wrap checks with bounded memory
    access. Each captured hit takes 293 guest instructions. Private construction
    now runs the integrator and ground resolver into that tape, reproducing all
    49 captured endpoints and every checkpoint while rejecting five invalid
    construction cases per frame. A lookup-or-build entry reuses all 35 same-world
    checkpoints across those frames and rebuilds at all observed world changes,
    preserving output on rejection. Read tracing isolated the player forecast
    dependency to the native sine table; optional private helper/table copies
    and 42 validated stage bindings preserve all 49 forecasts with that native
    table poisoned, with no observed external data reads. The experimental
    runtime now allocates/prepares the private workspace and retires its tape
    on lifecycle changes; PAL/NTSC binding, activation, retirement and relocated
    image tests pass. A checked runtime forecast entry selects the remaining
    interval and passes all 49 captured frames, PAL/NTSC interval reuse and
    40 atomic admission rejections. Runtime private candidate collection now
    matches all 49 cameras/candidate blocks, admits 28 zero/one-candidate
    selectors and rejects 21 ambiguous cases without native writes. Runtime
    impulse agreement now checks every eligible final-field combination:
    84 recorded and 405 damaged-fixture outcomes match independent replay,
    and 37 injected selector disagreements reject. The combined runtime actor
    forecast reproduces 20 recorded Hellfire endpoints, including both known
    retargeting errors, and rejects seven ambiguous states in explicitly
    normalized drained-boundary fixtures. A runtime presentation adapter now
    applies certified endpoints through the existing identity/discontinuity
    checks; 1,072 PAL/NTSC fractions and both retarget-path fixtures pass.
    The experimental frame loop now overlays only certified homing slots; a
    headless PAL 060 combat run publishes all 27 sampled frames without sampled
    timing/input faults, but draws fall to 11.71/s versus 14.29 in the earlier
    baseline window. Exact caching inside construction cuts its replay instruction
    count by 58–60% with identical outputs; the live 060 frame schedule and
    bitplanes remain identical, so no measured framerate gain yet. Future input
    uncertainty, further cost optimization, scene dependency gates and
    unvisited paths remain open, so live
    cross-field forecast reuse is not enabled. Broader input
    uncertainty, runtime cost, multi-candidate visibility and
    steering certification, field-rate projectile integration and near-pass
    validation remain open.
- **C7. Per-frame work that is not presentation.**
  - C7a. Effect spawning `+09B9A` (gameplay RNG) moves to the world tick; effect animation
    `+0BE5A` keeps its field-based timers. Replay countdowns and animation once per
    consumed field, excluding the native VBL/render writes under enhanced ownership,
    so shared slot lifetime and reuse cannot depend on drawing frequency.
  - C7b. The renderer's flight-end result `D3958`: work out what it detects, then evaluate it
    on committed state at the world tick, with or without drawing. Price evaluating it
    without drawing.
  - C7c. Map coordinate refresh: move it to consumed fields. The earlier
    “every 8 frames” description was wrong: +0489A increments a counter and
    calls +0475A when it is below 8, but +0475A resets it, so the normal
    zero-start path refreshes every map frame. The experimental runtime now
    calls +0475A after committed field motion in map-panel mode 1 and excludes
    that render-prefix mutation while retaining sprite updates and the
    two-buffer drawing countdown. Production activation remains pending.
  - C7d. **Implemented in the experimental runtime:** key code 12 (`+04EF2`,
    `D1548` toggle) is retired. It consumes the ordinary field-owned yaw tail
    and both command readers acknowledge it; it has no world primary or
    lifecycle boundary. A discovered boundary classification had still reset
    phase on each press; that is removed. PAL/NTSC assembled checks cover
    720 presses, and the installed PAL 68060 route confirms three presses
    with no rebase/loss or change to native speed words (6/3).
  - C7e. Leave the buffer-indexed dirty counters (2 frames = both buffers) as they are.
- **C8. Catch-up, pause and modal screens.**
  - C8a. When a render takes longer than a tick (the 68000 in heavy scenes), run overdue
    world ticks back to back up to a fixed bound. The player path still consumes every
    field.
  - C8b. Drop and report excess time. Exhausting the world allowance now
    yields to rendering with unread input and clock phase retained; only
    oversized field snapshots enter excess-time recovery. Pause, the map, menus and disk loads disable sampling,
    discard unread active history, and rebase, so they create no catch-up debt. Live Tab
    pause/release now freezes player/world/input-history state for 120 fields
    on PAL 68020 and NTSC 68060. Resume resets phase, motion fractions,
    delayed input, interval anchor and preview cache, then advances without
    simulating paused time. Live Escape from pause now also returns to native
    cleanup on PAL 68020/NTSC 68060, aborting one retained field without an
    extra completed field/world or a new epoch. Repeated Space map/display
    transitions suspend sampling, mark execution and resume with reset
    history. Separate deadline-aligned cases complete their retained world
    exactly once before rebasing. Controlled native landing and fatal ground
    impact now return to original cleanup at world 16 on PAL 68020/NTSC 68060,
    acknowledging the ending world once and keeping producers off afterward.
    The native "Take off again immediately" route now reloads and prepares
    the same arena on both setups, preserving mission ticks 16→32 while
    restarting runtime counters and retiring history again at the second exit.
    The native leave/debrief/service-record/new-mission route also passes
    PAL 68020/NTSC 68060: new tick/field/world counters start at zero, command
    cursors reset, and the controlled second flight advances 0→5→16 before
    retiring history again. Native rearm/refuel through the arming screen also
    passes both setups, preserving mission ticks 16→21→32 with fresh input
    cursors and no sampled active loss or extra rebase. Natural mission
    landings, weapon-induced death, repair and the remaining CPU/video
    lifecycle matrix remain open.
  - C8c. Reset prediction and player-step history at camera cuts, mission start, death and
    landing.
    Terminal flight retirement now explicitly invalidates player, actor,
    release and script prediction caches and clears the player endpoint
    history after suspension. Previously valid caches survived until the next
    activation. Native state and terminal diagnostics remain intact.
    Arena re-preparation and cached player motion also pass with original
    0658 hunks independently relocated into three layouts, at both field
    rates: 660 fields match across layouts with no retired-address access.
    Full relocated world/render execution and native loader placement remain
    outside that assembled check.
- **C9. Validate.**
  - C9a. **World equality across CPUs:** matched world-tick state on the 68000, 68020 and
    68060, with the A2 seed and the same field-stamped input, using the A4 gate. The
    authoritative state must not depend on render rate. Also run a diagnostic with drawing
    replaced by a field wait. The initial neutral PAL 68020/060 comparison
    exposed and fixed a verifier seed-policy omission in the private RNG.
    Worlds 100..102 now match player/RNG/mission-payload/alive state with
    neutral controls. An airborne route with field-scheduled engines,
    collective and joystick pulses now matches the same selected state on
    68020/060 and on 68020 with main drawing replaced by a field wait.
    Retained input records also agree. Full object state, combat, 68000 and
    the broader no-draw matrix remain open. The uncached 68000 active route fails
    equality under overload. Separating render-budget yields from true
    excess-time rebases reduces dropped time, but backlog discards remain;
    this is not accepted as cross-CPU equality. The current 68000 field-wait
    diagnostic reaches world 100 in 1,667 PAL fields without dropped time
    and matches selected state at worlds 100..102. A legacy captured input
    field differs while the other control bytes agree; the raw comparison
    remains explicitly non-passing.
    With motion caching, the controlled PAL rocket route now matches selected
    player/object/projectile, RNG and mission state at all 61 worlds 20..80
    on rendered 68000/020/060 and 68020 field-wait presentation, with no lost
    time/input. All expire at world 64. The corrected 68000 capture waits for
    runtime activation before deriving the input epoch; the earlier attempt
    scheduled controls 14 fields early and is excluded. Its remaining raw
    input mismatch is solely unused TR_RELATIVE, with consumed controls equal.
  - C9b. **Rate:** world ticks per second within a stated bound of 3.000, measured against
    the emulated clock, on PAL and NTSC, in all windows. The cached PAL rocket
    comparison has exact logical deadline fields on all three CPUs and field-wait
    rendering; worlds 20..80 span 1,000 logical fields. This alone does not
    prove completion rate against the native field counter. Broader windows,
    scenes remain open. The cached NTSC rocket repeat matches selected state
    and exact 3 Hz deadlines on 68020/060 and 68020 field-wait rendering.
    The 68000 NTSC route still overloads at world 27 (77 discarded history
    records, nine discarded phase units). A diagnostic 128-field limit only
    postpones failure until the history ring fills after world 42; the normal
    64-field limit remains unchanged. Profiling confirms cache reuse but
    identifies remaining field-owner, copy, distribution and raster cost. Direct key comparisons and
    grouped output copies now reduce sampled cache cycles/request by about
    46%, but only postpone the 68000 NTSC overload to world 30. Selected
    state agrees through world 29; this remains an unaccepted rate case. Validating
    motion distribution once per field then reduces its sampled cost/call by
    about 46%, postponing the first rebase to world 41 with selected state
    equal through world 40. Shared private owner/output storage now completes
    the NTSC 68000 route through world 80 with no loss or rebase and matching
    selected state, reducing sampled bridge/owner cost per field by about 29%.
    Actual completion nevertheless takes 1,220 native fields for 60 intervals
    (2.95082 Hz), with 32..62 fields of lag. Rate/latency remain unaccepted;
    logical deadline equality must not be mistaken for real-time throughput.
    Assembly-time specialization of the fixed motion field types reduces
    distribution cost per call by a further 35%. The matching NTSC 68000
    route retains all 61 selected states and no time/input loss; actual rate
    improves to 2.98013 Hz over 1,208 native fields, with 27..49 fields of lag.
    Responsiveness and broader rate acceptance remain open.
    Direct anchor copies from the same fixed-field list then reduce sampled
    player-owner cost by 21%. The matched NTSC 68000 run completes all 61
    selected state comparisons without time/input loss, at 2.99750 Hz over
    1,201 native fields. Lag remains 24..43 fields; the near-target average
    does not accept responsiveness or the wider timing matrix.
    Fixed-size exact cache comparisons now remove their per-longword loops,
    reducing sampled cache cost/request by 11%. The NTSC 68000 route still
    matches all 61 selected states, with no lost time/input, and completes
    60 intervals in 1,194 fields (3.01508 Hz). Lag is 18..38 fields in this
    sample; this remains too high for responsiveness acceptance.
  - C9c. **Responsiveness:** renders inside one world tick show a changing player pose and
    camera; count them, as Wing Commander's phase-9 gate did. Measure the delay from an
    input field to the first displayed frame that reflects it. A compiled PAL
    frame probe now records 36/89 same-world camera changes on 68020/060,
    with all eight short control pulses affecting completed frames. Four
    pulses per CPU press/release entirely between world deadlines. A neutral
    control confirms the roll response. Input-to-frame-completion spans are
    100..260/60..140 ms; those completion-only measurements are
    partial C9c evidence, not display-latency acceptance. NTSC repeats
    retain all eight pulses on both CPUs, with 27/66 same-world camera
    changes and completion delays 117..217/67..83 ms, without lost input.
    A subsequent PAL DMA probe matches each changed frame to actual bitplane
    scanout: four pulse delays are 13/6/5/9 fields on 68020 and 3/4/4/7..8
    fields on 68060. The final interval spans a capture gap. This is emulated
    scanout at field resolution, not host-display latency. The NTSC DMA
    repeat measures 11/13/11/7..8 fields on 68020 and 4/5/5/4 on 68060,
    again retaining all pulses without lost/discarded input or scheduler
    faults. Heavy-scene acceptance remains open.
    A current controlled NTSC draw probe now covers all five CPUs. Selected
    state matches at 61 world boundaries, without time/input loss. 020/030/
    040/060 complete about 7.20/11.58/12.84/12.85 fps and show 83/171/196/196
    same-world camera changes; completed-frame age is 6..8/4..6/4..5/4..5
    fields. These are completion measurements, not input-to-scanout delays.
    The 000 completes only 0.75 fps (one draw per four worlds), with frame
    age 28..46 fields. Replacing its drawing with a field wait narrows world
    completion lag from 24..43 to 10..11 fields while preserving selected
    state. Its responsiveness gate still fails despite near-3-Hz throughput.
    The matching PAL five-CPU probe also preserves all 61 selected world
    states and all common raw controls without loss or rebase. 020/030/040/
    060 complete 7.43/12.59/12.80/12.91 fps with 88/188/188/192 same-world
    camera changes; completed-frame age is 5..7/3..4/3..4/3..4 PAL fields.
    The PAL 000 completes 1.11 fps, drawing every two or three worlds with
    10..22-field frame age and no same-world camera changes. This controlled
    PAL/NTSC workload is covered; broader C9 acceptance remains open.
  - C9d. **Player path:** C4e's equivalence on every CPU, over all input combinations at
    several initial rates.
  - C9e. **Durations in play:** fuel, mission clock, weapon reload, lamp blink and effect
    lifetimes, per second. A CRT ordering defect is fixed: automatic map
    fallback now follows world-owned target selection, so intervening draws
    cannot undo pending targeting transitions. A PAL type-8 projectile route
    now matches motion, lifetime, allocation/generation and selected world
    state across 68020/060 for worlds 20..80; both release it at world 64.
    All 1,225 common retained input records match without loss or discards.
    A 68020 field-wait repeat matches the same authoritative state and expiry
    with 1,226 matching input records. Raw differences remain recorded for
    unused animation countdowns (cross-CPU) and projection scratch (no-draw).
    A controlled target-position event now exercises native type-8 impact,
    type-9 effect conversion and release on 68020/060 and a field-wait build.
    The occupied timer/frame/lifetime agree; release occurs 67 PAL fields
    after impact. The NTSC repeat agrees on both CPUs and with field-wait
    rendering, releasing after 60 fields under native field-count animation.
    Cross-CPU NTSC raw input differs only in unused TR_RELATIVE; all consumed
    controls agree, and that raw mismatch remains recorded. Natural guided
    hits, destructive damage, other effects, reload and the remaining
    duration/CPU/video matrix are still open.
    The occupied-guidance-slot launch restriction now has live pause/resume
    coverage on PAL 68020/NTSC 68060. Its counter freezes, releases after the
    exact remaining 24/22 consumed fields, and permits a new launch at world
    21 with one ammunition decrement. The earlier h6+4296 timer label means
    hit response, not reload; other weapon admission/reload conditions remain
    under audit. This does not close the overall weapon-duration requirement.
    The additional +9C42 firing-inhibit byte now matches native behavior in
    1,024 assembled cases, including all nonzero sign classes: launch and
    ammunition consumption stop while actor updates continue. It stays zero
    in all 610 current PAL/NTSC world captures. Its full writer catalogue and
    purpose remain unproven; it is not established as a timed reload.
    Fuel/clock now have a scoped five-CPU PAL/NTSC live-capture audit:
    all 600 adjacent world transitions preserve native reserve depletion
    (40/120 units every 16 ticks, zero otherwise) at fixed collective 40,
    both engines running and no damage. All 610 player clock samples equal
    the world tick; native conversion advances 20 seconds over worlds 20..80.
    Actual completion spans 19.78..20.02 seconds, separately from exact
    logical deadlines. Longer current-runtime PAL/NTSC 68020/060 captures
    now cover worlds 20..200: 724 live clock samples and 720 reserve transitions
    pass, including native clock conversion 00:59→01:00 at tick 180. Each
    same-video CPU pair matches all 181 selected states without active input
    loss or time discard. Actual 180-interval spans are 59.933..60.020 seconds.
    Clock UI at minute rollover, variable collective, engine failure, reserve
    exhaustion and whole-mission duration coverage remain open.
  - C9f. **Prediction:** zero-fraction poses equal committed state; predicted endpoints match
    the next native update in free motion. Exercise spawn, impact, slot reuse, pause/resume,
    death and landing. Extra frames must not change world state or gameplay RNG.
    A controlled PAL target-reposition fixture now releases and reuses slot 5
    on 68020/060: generation advances from 1 to 2, and the two natural expiries
    occur at worlds 64/116. Selected world state matches through world 130,
    with 2,058 matching retained control records and no losses/discards.
    Each CPU's 87 eligible cached forecasts match the next native update;
    19 live 68060 draw inputs after reuse use generation 2 and the correct
    forward fractions. The controlled PAL impact fixture also confirms that
    post-world prediction becomes ineligible when type 8 converts to effect
    type 9, without changing the allocation generation. Pixel/scanout, natural
    hits, other slots/weapons and lifecycle discontinuity coverage remain open.
    Active-rocket pause/resume now passes on PAL 68020 and NTSC 68060:
    actor/player/mask/cache state freezes for 120 fields; resume recaptures
    the committed actor data at phase zero with fresh generation metadata.
    All 38 eligible subsequent forecasts match native updates, and expiry
    remains world 64. Guided types, slot reuse across pause, other lifecycle
    exits and scanout continuity remain open.
    A controlled type-9 impact effect now also freezes its nonzero animation
    countdown during pause on PAL 68020/NTSC 68060. Actor bytes remain
    unchanged through resume; independent field-animation replay matches
    life/type/frame/countdown through release and later world 32. Prediction
    stays ineligible. Release follows the rebased world schedule; identical
    world labels across a phase reset are not assumed. Pixels, other effects
    and the broader lifecycle matrix remain open.
- **C10. Option.** `CUSTOM1=1`, exposed as the boolean **Enhanced framerate**,
  is the master opt-in for all framerate enhancements. Omitted/zero retains
  original timing and rendering paths. All future C/D/E optimizations must
  use this same gate. The new blitter patches and diagnostic native input
  producer are gated already; the original slave's cache policy and existing
  compatibility/protection fixes remain baseline behaviour.
  Current-runtime live checks now confirm omitted CUSTOM1 on PAL 68020 and
  explicit zero on NTSC 68060 preserve all 39 timing/blitter patch sites,
  leave the timing arena/table unallocated and continue native flight. An
  enabled capture changes all 39 sites, providing a positive control.

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

- **F1. Options.** Use CUSTOM options for:
  - the master boolean **Enhanced framerate**, CUSTOM1 (C10),
  - the renderer choice (E1c),
  - triple buffering (D4).
  
  Default: enhancements off. Renderer and buffering choices only apply when
  Enhanced framerate is enabled.
- **F2. All versions.** Apply each patch to every supported `gamemule`/`titlmule`/`scrnmule`
  version at its own offsets. Where a version cannot be tested, say so in the ReadMe.
- **F3. ReadMe and slave version.** Bump the version, add a history entry, and document the
  options.
- **F4. Final check.** Run the full matrix (68000, 68020, 68030, 68040, 68060) on all windows of
  A3: fps, pacing jitter, ticks per second and state equality. Also play through a full mission
  on the 68000 and the 68060. Resolve or independently validate the full-MMU
  asynchronous-blitter emulator limitation documented under B4. The reported
  68060 T-74 copy-protection graphics issue remains deferred at the user’s request.

### G. Optional: more of the world at field rate

Only after C is done, and only if C6's prediction of world objects shows visible errors at
25–50 fps. Move the free motion of the affected objects to field rate with C4's rules, while
their decisions, launches, hits and damage stay on the 3 Hz world tick:
- G1. Classify each quantity as a rate, an acceleration, a distance or a countdown, as Stunt Car
  Racer did in the playbook.
- G2. Audit each object type's motion code and its writers: AI, collisions, spawn and reset.
- G3. Validate behaviour in play, not only the arithmetic.

Raising the whole simulation rate, discrete logic included, is not planned. It would change
how often AI decisions and random draws happen, and so change how the game plays.
