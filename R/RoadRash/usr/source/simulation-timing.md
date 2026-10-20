# Simulation/presentation separation audit

C is in progress. This audit does not establish a working independent simulation.
The production slave still uses B's timing. No frame limiter is being added.
Addresses follow performance-plan.md's absolute-address convention.

## Existing boundaries and ownership

| Boundary | Existing behaviour | Requirement for C |
|---|---|---|
| `$87040` field hook | advances clock, consumes completed display records, latches frame delta, updates controls | keep display consumption and field sampling; separate simulation time and queued input |
| `$8747e` through `$875b6` | race timers, spawning, player/AI motion, collision, ranking | run once per simulation step, including when rendering misses fields |
| `$89138` camera update | derives view origin; also integrates/decays crash camera displacement | step-owned state, not a pure render helper |
| `$875bc` display gate | may skip geometry/rendering after simulation has already executed | must not authorize another simulation step by itself |
| `$875c8` through `$87730` | geometry, object lists, sound events, HUD and drawing | split pure presentation from event/timer side effects |
| `$87736` → `$aecba` | waits for next SOFT tick and swaps screen/copper pointers | retain vsync, without an added minimum frame interval |
| `$87748` → `$871dc` | publishes completion and rotates display records | remains presentation-owned; cannot choose simulation delta |
| `$a8c8c` | copies live race clock to `$a5d50` before each main-loop invocation | simulation consumers need the scheduled step's time |

The field input handler mutates `$a7262` (steering) and player flags at `$a5dc8`.
Collision routines also write steering (`$8c266`, `$8c310`, `$8c36c`). Merely saving
the latest input at render completion is insufficient: catch-up steps need inputs
from their own field boundaries, with collision-induced steering changes in order.
Pause and exit handling must remain responsive while rendering or catching up.

The camera writes `$a5d1e` and `$a7c02`. Physics and collisions read `$a5d1e`, including
`$8b792`, `$8b9ee`, `$8bc2a`, `$8be5e`, `$8bf4e`, `$8c3c8`, `$8c6c4` and `$8cefc`.
During a crash, `$89162` decays camera displacement once per call and `$89182`
integrates it from actor movement. Calling the camera once per render would therefore
preserve a gameplay dependency on rendering frequency.
Moving this call to a 50 Hz simulation did not by itself preserve its decay rate:
four calls leave approximately `(3/4)^4 = 31.6%` of the offset, whereas the
four-field original reference leaves 75%. The movement integration reads the
delta-scaled actor displacement, but the decay needs explicit elapsed-time
normalization. The correction and its reference are recorded below;
cross-render-rate hashes alone cannot detect this error.

`$8eff8`, called among rendering preparation at `$876c6`, consumes sound-event flags,
decrements `$a5d5e` using delta, and clears `$a598a/$a598b`. It must consume each
simulation step's events once, including intermediate catch-up steps. The audio
sequencer and music interrupts remain on their existing field/timer clocks.

## Direct delta references

The captured program disassembly contains **39 direct references** to `$a6f00`:
five writes, one zero check, and 33 consumers. In addition, `$8f5a6` reads its
low byte at `$a6f01` for the shared start/crash animation interpreter. This
inventory does not rule out other indirect aliases or frame-dependent updates.

| Addresses | Role |
|---|---|
| `$8660e`, `$86916`, `$86a48` | initialization writes |
| `$86fa0` | display-completion delta latch |
| `$87040`, `$87048` | zero check and minimum-one fallback |
| `$8749e`, `$8c0c4` | race/end countdown |
| `$8aecc` | actor `+$70` timer in sprite selection; clears `+$6a` bit 2 on expiry |
| `$8b438` | attack countdown |
| `$8b4b8`, `$8b4d6` | speed integration and longitudinal movement |
| `$8b756`, `$8b764`, `$8b8f0`, `$8bafe`, `$8bd1c`, `$8bd3a` | movement, crash and lateral/curve integration |
| `$8cbfc`, `$8cd70`, `$8cfd4` | special-actor movement and steering |
| `$8d318`, `$8d4cc`, `$8d536` | AI animation, countdown and motion |
| `$8dc6c`, `$8dcd6` | actor spawn/activation countdowns |
| `$8deaa` | police countdown |
| `$8e0d6`, `$8e1be` | speed reduction and actor `+$78` timer |
| `$8ef66`, `$8efd8` | collision velocity from displacement divided by delta |
| `$8f094`, `$8f138` | sound/event countdowns |
| `$90198`, `$902ae`, `$902c8`, `$903f4`, `$904c0` | actor action timers |
| `$90a28` | event/spawn countdown |

Keeping the core physics delta constant is necessary but insufficient. The
sprite-selection timer at `$8aecc`, camera integration and event consumption are
explicit examples outside the initial physics block.

The start-signal animation is also gameplay state. `$8a40e` calls `$8f552` while
building the banner; that routine calls the byte-delta animation interpreter and
sets `$a59d4` at `$8f57a` to start racer updates. A fixed-physics-step prototype
that leaves this animation on the render path produces the same player distance
but different opponent state. Per-step actor hashes first diverge at step 6;
with slower rendering, the same actor-state sequence begins five steps later.
The signal transition must run on simulation time; rendering should reuse its
selected sprite without advancing it. Moving that update into the provisional
four-field simulation produces matching hashes of all actor records for 199
straight-line steps at the two tested rendering rates, with a byte-identical
actor snapshot at simulation field 601. This is a diagnostic proof of the split,
not final validation or a selected production timestep. The longer steering/crash tape initially diverges at step 202 (simulation
field 809); queuing historical field inputs moves the first divergence to the
crash at step 357 (field 1429). Moving crash animation and sprite timers into
simulation then produces matching actor hashes for all 399 steps at tested
render intervals of 1, 3 and 4 fields. A 12-field rendering interval still
diverges, so these results do not yet establish independent timing under
multi-step catch-up. The nominal one-field test includes actual two-field
frames and is not proof of sustained 50 fps.

`$89d20` is not a pure draw-list builder either: `$89e26` clears actor crash bit 4,
and `$89e0e` calls `$8f190`, which advances crash/recovery state and updates rider
records. `$8a492` advances `$a808e`, the scenery cursor read by AI and collision
routines (`$8dfcc`, `$8e056`, `$8c49c`). These are additional split points, not
exceptions that can be excluded from gameplay comparisons.

Additional dependencies exposed by catch-up tests:

- `$89eec` writes actor `+$34`, a lean/orientation value read by physics at
  `$8c054`, `$8e372` and `$8e480`. Computing it for simulation is insufficient
  if rendering can subsequently overwrite it; authoritative writes need one owner.
- `$8c3b2..$8c408` reads the projected world-object list at `$a7c3e`, using
  `$a59fc/$a59fe` to locate its section. `$8b02e`, on the presentation path,
  builds those records and updates `$a59e4`, used by special-actor simulation.
  The collision check `$8c7f2` uses projected distance, scale and sprite data.
  Updating only the scenery cursor does not remove this dependency.
- `$8c48e` also combines world scenery at `$a808e` with a display-record pointer
  at `$a8092`. These inputs must describe the same simulation boundary.
- Sprite selection can clear actor `+$69` bit 4 at `$8aa90/$8abae`, and rider
  presentation clears `+$6a` bit 7 at `$8a11c`. These remain audit obligations;
  passing a tape without the relevant action does not validate them.
- The field input handler writes raw `$a598c`, which physics and attack handling
  read directly. Queueing steering alone is insufficient: IRQ polling must not
  overwrite the input belonging to an in-progress historical simulation step.

The catch-up prototype uses a provisional four-field quantum and no interpolation.
It is diagnostic code only; rendering its discrete positions faster does not yet
satisfy the smooth-presentation requirement. The normal slave remains unchanged.

## Diagnostic snapshots

`VERIFY` plus `VERIFY_C_AUDIT` captures one selected main-loop invocation at:

1. entry to `$8747e`, before simulation;
2. `$875b6`, before camera/geometry/rendering;
3. `$87748`, after swap and copper rebuild, before publishing completion.

`VERIFY_C_AUDIT_FRAME` selects the invocation (default 40). The `RRCAUD01` block
contains the invocation count (+8), captured-boundary bit mask (+12), captured
start address (+16), byte size (+20), three boundary field numbers (+24), selected
invocation (+36), then three snapshots (+40). The captured range is
`$a5900..$a873f`, including all 35 actor records, globals and projection scratch.

Copies alter execution time. Use functional runs only, not timing measurements.
Interrupts remain enabled, so differences include IRQ-written state; differences
identify dependencies, not the writing instruction. Missing boundary bits fail the
host check rather than silently accepting an incomplete capture.

The initial field-71 capture and acceleration capture at field 360 show no actor
record changes during presentation in those particular frames. They do show
camera/view, animation, display-list, projection and interrupt-clock changes.
These limited samples do not prove that actor records are presentation-read-only;
the sprite-selection timer above already disproves that generalization.

Raw snapshots and the host reader remain in ignored `tmp/dev/`. Normal builds
contain no audit hooks or storage and remain byte-identical to the final B build.

## Next implementation checks

- Measure fixed-step candidates against B's baseline and CPU budget, rather than
  picking a step from the desired rendering rate.
- Separate event, camera and sprite-timer updates from optional rendering.
- Queue field-timed inputs and preserve authoritative state during presentation.
- Check simulation-step boundary state across forced rendering intervals; use a
  separate presentation comparison because projection scratch is frame-dependent.
- Preserve elapsed-time remainder, pause/resume and race transitions, then validate
  throughput, controls, slow-machine catch-up and MMU configurations.

## Fixed-step diagnostic checkpoint

`VERIFY` plus `VERIFY_C_STEP` enables `verify_c_step.s`; it is not a runtime
feature. Use `CUSTOM2=1` (Enhanced framerate) and a first-race functional run, without `VERIFY_C_AUDIT`.
`STEP_FIELDS` defaults to four and `STEP_CAPTURE` to simulation field 601.
The `RRCSTEP1` block records the consumed field (+8), step count (+12), captured
field (+16), quantum (+20), then a frozen `$a5900..$a873f` snapshot (+24).
Immediately following is `RRCHASH1` and 1024 longword actor hashes, indexed by
step number (zero unused). Hashes cover every byte of all 35 actor records.
A missing capture or exhausted hash capacity must not count as a passing replay.

The prototype queues raw controls by active race field, replays inputs in order,
advances the original simulation with constant delta, and retains unconsumed time.
It owns camera integration, starter/crash animation, sprite timers and actor lean.
Before each step it rebuilds the road/world-object collision inputs through
`$8970e`, `$8b02e` and `$8a492`. This last dependency was material: without it,
the 12-field rendering test first differed in player collision flags at step 57
and later in player position. With it, all 399 actor hashes match between the
fast-render and 12-field test, including the steering/crash sequence; the frozen
actor snapshot at simulation field 1353 also matches byte for byte.

Evidence is in ignored `tmp/dev/tmp/c-collision-render1` and
`c-collision-render12`, with their comparison JSON. Both runs used functional
68020 emulation, not cycle-accurate hardware performance measurement. The test
compares equal simulation boundaries, not wall-clock snapshots during catch-up.

Remaining limitations include choosing and costing the quantum, interpolation,
other action/animation paths, input-ring overflow handling, reset and pause
semantics, complete event/clock comparisons, and the A2/A4/MMU regression suite.
The 2048-field input ring only flags overflow in this diagnostic; it is not a
production policy. Matching this one tape is not completion of C1, C2 or C3.

### Clock, track events and quantum cost

The live `$a5d4c` field count schedules work. The stopwatch at `$a5d58..$a5d5b`
now advances in simulation, retaining the original 60-field BCD second and
finish-bit check. Otherwise an IRQ would observe a finish at a different live
field depending on how far rendering delayed simulation. Track-section events
formerly dispatched by `$a8c7c..$a8cbc` also run at each step, including catch-up.
Their high-water position remains `$a5d38`. The input replay/overflow flags are
reset when installing the race hook.

The two-field-quantum steering/crash replay in `c-clock-render2` and
`c-clock-render12` matches all **798 common actor hashes**, and its actor,
stopwatch and displayed-rank snapshot at simulation field 1457 is identical.
The faster run had completed one additional step at live field 1600; only common
completed steps were compared. This checks snapshot clock/rank agreement, not
all event counts or end-of-race behaviour.

`STEP_NO_HASH` disables the per-step actor hash for cost experiments;
`STEP_CAPTURE=0` disables the snapshot. These runs cannot prove state agreement.
Initial cycle-configured measurements over active fields 100–1000, with throttle
held, are recorded in `tmp/dev/tmp/c-cost-{cell}-q{quantum}/cost.json`:

| Simulation quantum (fields) | A500 rendered fps | A1200 + Fast rendered fps | Result |
|---|---:|---:|---|
| 1 | 0.00 | 4.89 | A500 backlog grows to 131 fields; no frames completed in the window |
| 2 | 4.56 | 8.89 | both keep advancing and rendering; sampled backlog 5/3 fields |
| 4 | 7.00 | 11.28 | both keep advancing and rendering; sampled backlog 7 fields |

These are diagnostic throughput observations over this window, not final
production performance or every-CPU validation. A point sampled during a step
can include work still in progress. The one-field quantum is rejected for the
current implementation on A500: it cannot sustain real-time simulation, even
before interpolation. The two-/four-field choice still needs baseline and
broader-scene comparison. A larger quantum requires presentation interpolation;
it must not become a rendering-rate limit.

The four-field diagnostic also passes keyboard and CD32 steering-release and
pause/resume smoke tests (`c-clock-input-keyboard`, `c-clock-input-cd32`). The
active field counter stays at 161 throughout the paused observation, and resumes
on input. These smoke tests do not measure complete input-to-display latency or
prove transition/restart behaviour.


### Rejected interpolation experiment and actor-isolation evidence

The former `STEP_INTERPOLATE` experiment enabled interpolation for two- or four-field
quanta. It keeps previous and current actor positions, draws an intermediate
position with a one-step display delay, and restores the authoritative actor and
camera records before publishing the completed frame. This is still diagnostic,
not a released option or a rendering-rate cap. Other mutable presentation globals
and action paths still need the full ownership audit.

The `RRCVIEW1` block near the `$875c8` hook records frame count (+8), last fraction
index (+12), four fraction histogram counters (+16), and four triples of previous,
current and rendered player position (+32). The observed fractions include 1/4
and 3/4, with exact expected positions; the view is not simply repeating whole
simulation positions. `c-interp-pose` records that check, including the failed
initial isolation comparison.

Restoring actor state exposed the rider spark flag: rendering cleared `+$6a`
bit 7 at `$8a11c`, causing the initial interpolated/non-interpolated replay to
first differ at step 355. The diagnostic now consumes that event in simulation
and stores a separate spark bit for drawing. After this split, all 399 hashes
match between `c-spark-interp` and `c-spark-base` on the steering/crash tape.
The earlier `c-interp-render1/12` comparison also matched across rendering rates.
The final crash screenshot was inspected for correct road, rider, bike and HUD
presentation; this is not complete visual validation of every scene or action.

### Attack-state preparation

Pose selection at `$89d20` also owns attack-state transitions (`$8aa90/$8abae`)
and the `$a5991` sound-event gate. The diagnostic now evaluates it once per
simulation step, after derived lean and crash state, including catch-up steps.
The visual phase bytes at `$a598d/$a5990` derive from simulation time rather than
incrementing on every draw. The original crash-bit clearing branch runs only
when called from simulation. Complete action/weapon coverage is still pending.

`c-attacks-before1/12` exercises fire-button attacks with both steering
orientations. The tape changes 304 actor hashes relative to the no-attack tape,
and sampled player flags confirm active attack states. Its actor hashes already
match between those render intervals; this alone does not prove sound-event
ownership. After moving pose/event preparation, `c-attacks-pose1/12` also matches
all 399 actor hashes and the frozen actor snapshot. Audio event counts remain a
separate verification requirement. These tests used the now-rejected delayed
interpolation experiment; they remain evidence about simulation ownership, not
acceptance of its presentation latency.


### Current direction: forward prediction without deliberate display delay

The user rejected the one-step interpolation delay. `STEP_EXTRAPOLATE` replaces
that experiment: it draws the current position plus the observed per-field motion
for the elapsed remainder, never deliberately drawing one simulation step behind.
Authoritative state is still restored after drawing. A crash-state transition or
zero current speed suppresses prediction for that actor. The simulation quantum
is still provisional; this change alone does not resolve input waiting for a step.
An 80 ms input delay is also unacceptable and must be measured independently.

Earlier interpolation results above are historical isolation evidence only.
They do not validate the prediction path, its collision corrections, or latency.


Forward-prediction replay `c-predict-render1/12` matches all 399 actor hashes.
The recorded moving-player positions satisfy current + elapsed-fraction × motion,
including quarter- and three-quarter-step predictions ahead of current position.
These results verify prediction arithmetic/isolation on that tape, not latency.

Following the user's timing clarification, the primary candidate is now one PAL
field per simulation step: **50 Hz with catch-up**. `STEP_FIELDS` defaults to one.
The earlier A500 overload is a compatibility finding, not a reason to impose a
larger simulation quantum on accelerated Amigas. Accelerated-machine cost and
50 Hz gameplay validation must decide the implementation. Forward prediction is
only a diagnostic alternative for larger quanta; delayed interpolation is removed.

The hardware policy is now two paths: original timing on 68000, and fixed 50 Hz
simulation on 68020+ with Fast RAM. Diagnostic hardware dispatch is implemented
as described below; production integration remains open. These experiments do not change the normal
slave. The loader's existing `expansion_memory=$80000` is a game address in Chip
RAM, not evidence of an allocated Fast RAM region.

The `c-50-target-*-q1` cost runs, with caches enabled and diagnostic hashing and
snapshot copying disabled, reached field 1000 with simulation cursors 999
(A1200 Fast), 999 (030/50), 998 (040/25), and 999 (060/50). At the sampled fields
300, 600, and 1000 none had growing simulation debt. This supports continuing the
50 Hz accelerated candidate, but does not establish correct gameplay speed or
input latency. Rendering still needs optimization; these are emulator results,
subject to the CPU-model limitations recorded in the baseline.

The full attack/steering tape now runs at one-field simulation steps with
presentation intervals of 1 and 12 fields (`c-50-full1`, `c-50-full12`).
All **1,596 common consecutive actor hashes match**, including the previously
unrecorded portion beyond tick 1,023. The actor snapshot at field 1,457 also
matches. Other snapshot bytes include presentation state and are not identical;
this is an actor-state result, not a whole-state or event-count equivalence claim.
Both runs use fast functional emulation, not hardware throughput measurements.

The diagnostic hash record is now `RRCHASH2`: an eight-byte marker, a longword
slot count, then that many longword hashes (slot zero unused). The default is
2,048 slots, configurable with `STEP_HASH_SLOTS`. The harness reads that capacity
and rejects runs that exceed it, instead of silently comparing a prefix.
The builds use `VERIFY_B`, `VERIFY_C_STEP`, `STEP_CAPTURE=1457`, and
`VERIFY_FRAME_PERIOD=1` or `12`; `STEP_FIELDS` remains its default of one.
The input fixture is `tmp/dev/fixtures/c-attacks.json`.

The simulation lean pass now follows the original list eligibility rules at
`$89d64..$89de4`: secondary actors require `$56=-1`; the third list at `$941e2`
is considered from field 1,800, with its activation and camera-position checks.
Previously that third list was omitted and secondary eligibility was unchecked.
Extending throttle to field 1,950 (`c-attacks-late.json`) gives **1,944 matching
consecutive actor hashes** at presentation intervals 1 and 12, with identical
actor snapshots at field 1,901 (`c-50-late1/12`). The earlier 1,598-tick prefix
is unchanged by this correction. The special actor is inactive in the captured
snapshot, so a scenario with it active and visible is still required.

## Demo and input dispatch correction

The original demo exit branches at `$87104` and `$8710a` target `$87110`.
The former diagnostic `PL_PSS $710c,...,4` overwrote that target inside its
replacement instruction sequence. The field hook now replaces the complete
demo/player dispatch at `$870dc..$87115`, returning the exit flag's condition
codes to the existing branch at `$87116`. It preserves the 3,600-field demo
timeout and native demo input polling. Demo simulation skips the human input
queue, which has no producer while the AI drives the player.

`c-demo-race-regression` matches all 1,598 recorded human-input actor hashes
against `c-50-full1`. Keyboard and CD32 steering/release and pause/resume checks
pass (`c-demo-keyboard`, `c-demo-cd32`); the active field clock remains 161
through the paused interval. `c-demo-transition-intro` observes the demo advancing
from field 163 to 463, exits it with fire, then reaches a normal race at field 100.
The first unattended test stayed at a pre-race message; the successful harness
first presses fire after 1,000 boot fields, then waits for the demo.
`c-demo-timeout-verified` also exits without input at race field 3,598, matching
the native 3,600-count limit with the observed initial two-count offset, then
starts a normal race. Cleanup clears the demo timer, so the timeout check uses
elapsed fields rather than expecting its post-exit value to remain 3,600.

All C simulation patches now require the boolean `CUSTOM2=1` (Enhanced framerate).
Earlier experiments using `CUSTOM2=0` predate this master switch. With it off,
normal and C diagnostic builds retain original timing; instrumentation may still
observe execution. Future C–F optimizations must obey the same switch.
The `toggle-normal-off/on` and `toggle-step-off/on` boot checks inspect the
simulation entry, delta latch, animation, swap and input-dispatch instructions.
Both off builds retain the original instructions at all five sites. The enabled
normal build installs B's patches; the enabled C build installs C's patches and
keeps the original swap without B's extra floor. `toggle-step-replay` matches
all 1,598 actor hashes from the pre-switch human-input replay.

## Crash-camera decay on elapsed time

The C path now replaces only the recovery-decay branch at `$8915a`.
Its reference is the original A1200's four-field cadence, where each call
retains 75% of the camera offset. A one-field update subtracts
`floor(offset * 4548 / 65536)`: the coefficient approximates
`1 - (3/4)^(1/4)`. Four updates retain 74.9994095% before integer rounding.
Larger diagnostic quanta repeat the same one-field operation. This deliberately
replaces the old hardware-dependent recovery rate with one consistent rate;
it does not slow input or add a presentation delay. The movement branch already
reads delta-scaled actor displacement and is unchanged.

The signed product is split into signed high-word and unsigned low-word
products, avoiding overflow at either 32-bit limit with 68000 instructions.
`VERIFY_C_DECAY_TEST` checks ten signed cases in the actual emulator, including
both limits, zero and both signs. One- and four-field results match independent
host integer arithmetic (`c-decay1/12`, `c-decay4`). For offset -28,672, four
normalized updates give -21,502 versus the original -21,504: two fixed-point
units of rounding difference.

The attack/crash tape still gives **1,596 identical consecutive actor hashes**
between rendering intervals 1 and 12. Relative to the previous, overly fast
decay, actor hashes first change at tick 1,263; this is an intentional timing
correction, not a claim of byte equivalence to that prototype. The normal slave
is byte-identical to the master-toggle build; this correction remains diagnostic
until the rest of C is validated. Large extrapolation snapshot buffers now follow
the executable helpers so their optional build retains valid PC-relative ranges.

## Hardware selection inside Enhanced framerate

The C patch list is now separate from the common loader/input fixes. The loader
applies it only when `CUSTOM2` is enabled, `WHDLTAG_ATTNFLAGS_GET` reports
`AFF_68020`, and the allocated slave hunk lies in a supported Fast RAM window.
Otherwise it leaves original timing intact, including on 68000 machines with
Fast RAM. Diagnostic frame-pacing/skip hooks obey the same selection.

This checks the memory actually holding the slave, without probing unallocated
addresses or reserving extra memory while enhancements are off. The conservative
address windows are `$200000..$9fffff` and `$1000000` upwards; Chip RAM and the
reserved upper-24-bit window (including `$c00000` slow RAM) are rejected.
This is a conventional Amiga address-map check, not a generic OS memory-type
query. Unconventional Fast RAM inside the rejected window falls back. WHDLoad's
local developer autodoc explicitly permits `ws_ExpMem` to come from Chip RAM,
so a nonzero optional expansion allocation would not be a valid substitute.

`RRCSEL01` records Custom2, AttnFlags, slave address and selection reason
(0 disabled, 1 CPU, 2 memory placement, 3 selected). Functional boot checks:

| Configuration | Slave location | Result |
|---|---:|---|
| 68000, Chip + slow | `$d72ac0` | original, CPU |
| 68000 + 8 MB Fast | `$9f2ac0` | original, CPU |
| 68020, 2 MB Chip only | `$1f12c0` | original, memory |
| 68020, Chip + slow, no Fast | `$d72a98` | original, memory |
| 68020 + 8 MB Fast | `$9f2ac0` | C selected |
| same, Custom2 off | `$9f2ac0` | original, disabled |
| 68040/MMU + Fast | `$9f2000` | C selected, TC=`$8000` |
| 68060/MMU + Fast | `$9f2000` | C selected, TC=`$8000` |
| 68040/MMU, 32-bit Fast only | `$407f2000` | C selected, TC=`$8000` |

Evidence is under `c-select-*`. The slow-only check also builds the diagnostic
12-field pacing hook and confirms it is not installed on the fallback path.
The initial `c-select-a1200-slow` attempt did not actually enable slow RAM in
the preset; `c-select-slow-only` checks the effective configuration and allocated
slow-RAM address. The selected C path matches all 1,598 actor hashes from the
camera-normalized replay (`c-select-replay`). The normal slave remains
byte-identical to the master-toggle build. These are functional dispatch checks,
not a replacement for the full C regression/performance matrix.

## Input-to-frame handoff measurements

`VERIFY_C_LATENCY` records the first RIGHT input after reset through polling,
historical input replay, simulation completion, frame construction and return
from the original vsynced buffer swap. It is optional instrumentation in the C
patch list, never an extra user mode. `RRCLAT01` contains fourteen longwords
after its marker; the layout is documented in `verify_c_latency.s`.
The latency builds disable actor hashing and frozen snapshot copies.

The host accelerates from field 100, injects RIGHT at field 300, and inspects the
first frame constructed from a simulation tick that consumed that input. Times
below are field-count differences multiplied by 20 ms. They have field
resolution, are single-phase samples rather than latency distributions, and
measure buffer handoff, **not completed scanout or a proven first changed pixel**.

| Emulator configuration | Input sampled | Input replayed | Simulation done | Frame starts | Swap starts | Swap returns |
|---|---:|---:|---:|---:|---:|---:|
| Fast functional execution | 20 ms | 20 ms | 20 ms | 20 ms | 40 ms | 60 ms |
| A1200 Fast + Cache | 20 ms | 40 ms | 40 ms | 80 ms | 140 ms | 160 ms |
| 030/50 + Cache | 20 ms | 60 ms | 60 ms | 100 ms | 140 ms | 160 ms |
| 040/25 + Cache | 20 ms | 20 ms | 40 ms | 40 ms | 80 ms | 100 ms |
| 060/50 + Cache | 20 ms | 20 ms | 40 ms | 40 ms | 80 ms | 100 ms |

Evidence: `c-latency-functional`, `c-latency-<cell>/latency.json`.
040/060 numbers retain the emulator-model limitations documented in the baseline.
All samples replay the input for historical field 301, so there is no deliberate
four-field input quantum. Nevertheless the measured presentation wait is too
large to claim the requested response goal is met. Catch-up work and rendering
cost must be reduced before promoting this candidate. The probe leaves all 1,598
actor hashes unchanged (`c-latency-regression`); disabling the probe yields a
byte-identical diagnostic slave to `c-select-build`.

The A1200 Fast + Cache flat-PC profile over fields 100–300
(`c-latency-profile/aprof.txt`) records 199 simulation updates and 19 renders.
Geometry, actor-pose preparation and world-object projection each execute 218
times: once per simulation update plus once per render. Flat instruction-address
ranges account for 36.63% of recorded units in `$8b486..$8eff7` (physics/AI),
9.28% in `$8b02e..$8b37d` (world-object projection), 6.21% in
`$89d20..$8a491` (actor pose/selection), and 5.16% in `$8970e..$89a9b`
(road geometry). These are disjoint flat-PC costs, not inclusive call-tree
estimates. Stack/register traffic also appears prominently in the Chip-access
profile. Moving the CPU-only stack to public memory is a concrete next
experiment, subject to D3e's stack/interrupt/DMA audit; redundant projection and
pose work remain further candidates.

## Optional expansion-memory stack experiment

`VERIFY_C_FAST_STACK` is a diagnostic cost experiment inside the selected C path
and the Enhanced framerate toggle. It requests 20 KiB of optional `ws_ExpMem`
(`-$5000`); 16 KiB is usable stack, with 16-byte guards on both sides. The stack
switch replaces the native `$a876c` initialization, which already discards the
trap frame. Interrupts stay masked during initialization, and the original
`SR=$2700` is restored before continuing at `$a8776`. No live stack is copied.
The allocation must be in the same conventional Fast-memory windows used by the
C selector; otherwise this hook establishes the original Chip stack. Normal
builds neither allocate this memory nor install this hook.

The first attempt put the stack in the public slave hunk. WHDLoad rejected it
on level-2 interrupt entry with “Bad stack pointer”; that attempt is discarded.
A CPU-accessible public address alone is insufficient for a WHDLoad stack: use
its managed BaseMem/ExpMem allocation. The corrected experiment uses optional
ExpMem, checks its actual placement, and retains the original stack on failure.

The `RRCSTK01` diagnostic header stores stack size, initialization count, bottom
and top at offsets +8, +12, +16 and +20. The host checks both guard patterns and
measures the deepest overwritten pattern. A short replay is not a proof of a
maximum stack depth. Static inspection found register/argument saves and local
words on the native stack, including `$83f8c..$83fb8` and `$b0628..$b0654`; the
latter preserves sprite/screen addresses rather than creating stack-based DMA
buffers. A complete executed DMA-pointer/lifetime audit remains required by D3e.

Functional checks:

- All 1,598 attack/steering/crash replay hashes match `c-select-replay`.
  The stack at `$9fa010..$9fe010` uses 224 bytes in that replay, with intact guards.
- Keyboard and CD32 pause/resume preserve the stopped field counter; steering
  and release work. Demo entry, fire exit and subsequent human race work.
- 040/MMU and 060/MMU with only 32-bit Fast memory reach a race, report TC=`$8000`,
  and return to the AmigaDOS prompt via the actual Help quit key. The respective
  stack bottoms are `$9fa010` and `$407fa010`; guards remain intact.
- With the master toggle off, all checked timing hooks and native stack setup
  remain original. A Chip-only 020 also preserves native timing and stack setup
  (`c-stack-chip-fallback`). Compiling without this experiment reproduces the prior
  latency diagnostic binary, and the normal slave remains byte-identical.
- The optional four-field extrapolation configuration still assembles. Its large
  data blocks require a full-width relative offset when locating `_expmem`.

A1200 Fast + Cache, accelerating over fields 100–1000 with hashing/capture off:

| Candidate | Frames during the 900-field interval | Average fps |
|---|---:|---:|
| Chip stack | 114 | 6.33 |
| Optional Fast stack | 153 | 8.50 |

This is a 34.2% throughput gain for this workload, not a 50 fps result or a
cross-machine performance claim. The field-300 RIGHT latency sample gets worse:
20 ms poll, 60 ms replay, 80 ms simulation completion, 140 ms frame start,
200 ms swap entry and 220 ms swap return, versus 160 ms swap return with the
Chip stack. A single input phase cannot characterize the distribution; neither
result meets the response target. Increased throughput does not establish lower
input latency. Keep the experiment optional until broader validation and further
simulation/render cost reductions are complete.

Evidence: `c-stack-final-replay`, `c-stack-final-cost-a1200-fast+cache-q1`,
`c-stack-baseline-cost-a1200-fast+cache-q1`, `c-stack-final-latency-a1200-fast+cache`,
`c-stack-input`, `c-stack-pad`, `c-stack-demo`, `c-stack-040-mmu-quit`,
`c-stack-060-z3-mmu-quit`, `c-stack-final-off`, and `c-stack-disabled-build`.
The final full-width header-address correction is checked again by
`c-stack-ready-replay` and `c-stack-ready-latency-a1200-fast+cache`.

## Exact road-width lookup experiment

`VERIFY_C_GEOMETRY_LUT` requires the selected C path and
`VERIFY_C_FAST_STACK`. It increases optional ExpMem from 20 to 40 KiB and places
an 8,193-word table at allocation + `$5000`. Entries 1..8192 are the exact
unsigned quotients `7168 / depth`; entry zero is unused. The original geometry
loop's divisor is `256 - fraction + 256*row`, with fraction 0..255 and row 0..31,
so every possible divisor is covered without approximation.

After initialization, the experiment replaces `$8984e..$89859` with a 68020
full-extension indexed `MOVE.W (table.l,ZA0,D6.W*2),$64(A3)` and a NOP. This
avoids 32 constant-numerator divisions per geometry call without changing the
other projected coordinates or collision calculations. The next native
instruction clears D2, so its former division result is not live. The original
store's condition flags are preserved. `resload_FlushCache` follows code writes
before the game resumes. No code is changed unless C was selected and optional
ExpMem has a verified Fast address. The master-off and Chip-only fallback keep
the original division instruction. Disabling this experiment reproduces the
stack-only diagnostic binary exactly; normal builds remain unchanged.

A subroutine lookup was rejected: its entry/register-save overhead reduced the
A1200 Fast + Cache interval to 148 frames (8.22 fps), against 153 (8.50 fps) for
the stack-only candidate. The direct indexed version produces 156 (8.67 fps)
over the same fields 100–1000. This is only a 2% additional gain in this workload.
The final build's RIGHT-at-300 sample returns from swap at 160 ms, still too slow
to establish the response target. Earlier binary layouts yielded 120 or 140 ms
single samples; those phase-sensitive results are not latency distributions.

The host verifies every table entry against independent integer division and
checks the actual patched instruction/address. Fast-render replay matches all
1,598 actor hashes; the 12-field rendering experiment matches all 1,596 completed
steps against the same reference. 040/MMU and 060/MMU with 32-bit Fast memory
pass table checks, preserve stack guards and quit through Help to AmigaDOS.
The extrapolation combination also assembles. Evidence: `c-width-lut-cost-*`,
`c-width-inline-replay`, `c-width-ready12-replay`, `c-width-ready-cost-*`,
`c-width-ready-latency-*`, `c-width-040-mmu`, `c-width-060-z3-mmu`, `c-width-off`,
`c-width-chip-fallback`, `c-width-disabled-build`, and `c-width-extrap-build`.

The remaining two-field cadence in fast functional execution still needs a
handoff audit before claiming C2c's uncapped rendering requirement. The native
swap waits for a new SOFT tick at `$aecea`, then changes the live copper pointers
at `$aec78`; completion records are published later at `$871dc`. Removing the
wait without redesigning that handoff would risk tearing. The next timing work
must establish when completed buffers become visible and when each buffer can
be reused, rather than treating a higher throughput sample as proof of uncapped
presentation.

## Vsync handoff trace: two-field cadence is rendering cost

The follow-up trace resolves the concern above without changing the safe swap.
In `c-handoff-full-trace`, a completed swap returns at field 301, beam line 250;
record publication follows at line 253. The next frame starts in that same field
at line 303, with its producer record already free. It reaches the swap at field
302, line 299: the next SOFT tick at line 250 has already passed. Waiting for
field 303 is therefore a missed deadline, not a two-field pacing condition or a
wait for the previous completion record. The sampled swap fields are
301,303,305,307,309,311,313,315.

The existing `VERIFY_SKIP_RENDER` cost diagnostic omits `$afd60` while retaining
simulation, geometry, publication and the original swap. In
`c-handoff-skip-trace`, successive swaps complete at fields 301,302,303,304,305,
306,307,308, always at beam line 250. The producer begins the next frame before
the previous record is consumed, using the other free record. At every sampled
render entry its ready flag is zero; front and back buffer pointers remain
distinct and alternate at swaps. The previous consumer record is released at
the next SOFT interrupt. These observations prove that the retained handoff can
support one presentation per field without an artificial two-field floor.
They do **not** prove full-render 50 fps: the diagnostic deliberately omits work.

The trace uses breakpoints at `$875c8` (frame construction), `$87736` (swap entry),
`$8773c` (swap return), `$871dc` (publication), and `$8713a` (consumer release),
recording active field, beam, SOFT counter, both ready flags, pending drain counts
and buffer/record pointers. Preserve the original blanking-safe swap; simply
removing its wait would write the live copper list at unsafe beam positions.
