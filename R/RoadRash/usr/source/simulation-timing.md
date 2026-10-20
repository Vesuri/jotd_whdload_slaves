# Simulation/presentation separation audit

C is in progress. The normal beta now uses the shared independent simulation
on supported hardware when Enhanced framerate is enabled. Runtime integration
and remaining regression/latency checks are not yet a completion claim.
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
At this stage the 2048-field input ring only flagged overflow; the explicit
failure policy below supersedes that behavior. Matching this one tape is not
completion of C1, C2 or C3.

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

## Discrete sound-request audit across rendering intervals

`VERIFY_C_EVENTS` records five discrete dispatch sites in `$8eff8`: engine/crash
sound start (`$8f06a`), stop (`$8f080`), primary effect (`$8f0be`), secondary effect
(`$8f0de`) and siren start (`$8f120`). Wrappers preserve the original registers and
condition flags before tail-calling the original audio entry. They are installed
only by the selected C patch list under Enhanced framerate. The trace resets at
race initialization and is excluded from normal builds.

`RRCSEV01` contains count, overflow count, capacity (1024) and record size (8) at
+8, +12, +16 and +20. Records begin at +24: historical simulation field (long),
kind (word, 1..5 in the order above), parameter (word). The stop parameter is
normalized to zero because that entry has no sound-number argument. A host must
reject overflow rather than compare a silently truncated stream.

`VERIFY_FRAME_PATTERN`, together with `VERIFY_FRAME_PERIOD`, cycles diagnostic
presentation waits through 1,2,3,4,12,2,16,4 fields. It keeps the original vsync
swap and changes no simulation quantum. This is test instrumentation, not a user
frame-rate mode. Actual frame histograms must be checked: requesting period 1
with full drawing produces two-field frames in the functional configuration.

The attack/steering/crash tape produces these identical requests for periods
1,2,3,4,12 and the varying pattern:

| Simulation field | Kind | Parameter |
|---|---|---|
| 1096 | primary effect | 2 |
| 1122 | engine/crash start | 5 |
| 1263 | stop | 0 |

All overlapping completed actor hashes match (1,596–1,598 depending on the
consumer's position when the host stops). At the fixed field-1457 snapshot,
all 35 actor records, the simulation time, stopwatch, camera position,
crash-camera offset and rank cells match exactly. The varying run has actual
2,3,4,12,16-field frames, so this includes repeated multi-step catch-up rather
than only a steady-rate comparison. Evidence: `c-events{1,2,3,4,12}-replay` and
`c-events-variable-replay`; their `step.json` files include the event streams and
actual frame histograms. `c-events-disabled-build` reproduces the earlier
latency diagnostic byte-for-byte, and the normal slave remains unchanged.

These results cover the sound requests exercised by this tape, not every event:
secondary attacks and siren start have not occurred in these samples. The trace
also does not measure sample audibility, sequencer interrupts, volume updates,
or stop requests from pause/exit paths outside `$8eff8`. Those coverage limits
remain open; matching actor hashes alone must not be used to close them.

`c-events-onefield-replay` additionally omits the existing expensive draw call
with `VERIFY_SKIP_RENDER`: its measured histogram has 1,600 one-field frames
(after startup), and all 1,598 common actor hashes, the same fixed-boundary state
and all three requests match the full-render cases. This supplies an actual
one-field scheduling comparison; it is not a full-render throughput or visual
quality result.

## Long replay hash collection and siren coverage

`STEP_HASH_RING` makes the diagnostic hash buffer reusable for long runs without
increasing its memory footprint or crossing 68000 PC-relative addressing limits.
It requires hashing and a power-of-two slot count. The frozen snapshot stays in
the same position; the following header becomes `RRCHASH3`: capacity at +8,
last completely published simulation step at +12, and the hash ring at +16.
Step N uses slot `N & (capacity-1)`. The producer stores the hash before publishing
N, so an interrupted, partially executed step cannot be mistaken for a completed
hash. Race reset clears the published counter. The default linear `RRCHASH2`
format is unchanged when the option is absent.

The host collects periodically, rejects a backward counter or a gap larger than
the capacity, and assembles a complete linear trace. `c-long1-replay` and
`c-longvar-replay` collect through two wraps of the 2,048-slot ring over 6,000
active fields. All 5,985 common completed actor hashes match. Their first 1,598
hashes also match the earlier linear-buffer replay, and the fixed field-5501
actor, clock, camera and rank snapshots match. `c-ring-disabled-build` remains
byte-identical to `c-events1-build`.

Both longer runs add a siren-start request (kind 5, parameter 10) at simulation
field 4878, with the earlier three requests unchanged. Thus siren dispatch now
has cross-render-rate coverage. The special actor remains inactive in this
route; its timer threshold alone is not evidence of an exercised special actor.

The route also exposed a test-input issue: holding UP after a crash keeps the
player running away from the motorcycle. This is native behavior: `$8b6ce`
checks raw controls, and `$8b6ee` calls the manual running handler `$8b7a8` when
input is held, bypassing the automatic return at `$8b6f4`. The long screenshot
shows the rider running off-road; both traces retain state 3 accordingly. Further
routes must release controls during recovery to cover remounting and subsequent
riding. Do not count mere time spent in state 3 as completed crash recovery.

## Special actor, remounting and armed sound coverage

The recorded `c-road-drive.json` route follows the road and releases controls
during a crash. Its input was generated once from the reference run, then replayed
unchanged for the varying-cadence comparison. The special actor at `$a6e60`
becomes active (flags `$4000`) near fields 3000 and 5000. All 5,996 common
completed hashes and all 32 sound requests match between `c-long-drive` and
`c-long-drive-var`. This exercises special-actor activity rather than merely
waiting for its timer threshold.

`c-road-recovery.json` extends that recorded input to field 7000, retaining
released controls after field 5780. `c-recovery1-replay` and
`c-recoveryvar-replay` match all 6,992 common completed hashes, all 32 sound
requests, and the frozen field-5501 actor, clock, camera and rank state.
Both reach crash state `$ff` by field 6500 and remain there at 7000.
Both final screenshots show the player remounted on the motorcycle. This route
uses ordinary controls without injecting game state. It establishes completed
recovery across render cadences, not race completion or subsequent racing.

The optional `VERIFY_C_SEED_ATTACK` fixture requires `VERIFY_C_EVENTS` and seeds
an armed player attack at historical simulation field 501. Native action,
pose-selection and sound-dispatch code then runs normally. This is a synthetic
boundary test, not evidence that the player naturally acquired a weapon.
`c-armed1-replay` and `c-armedvar-replay` match all 1,597 common completed hashes
and the frozen field-1457 state. Both request secondary effect 6 at fields
501, 641 and 841, followed by the same three original crash-tape requests.
Neither trace overflows. With the fixture disabled, `c-seed-disabled-build`
is byte-identical to `c-events1-build`, including the unchanged normal slave.

Together with the earlier siren route, these tests exercise all five traced
request kinds. Audible playback, pause/exit sound behavior, race finish and
restart still need separate validation.

## Input history exhaustion

The input producer now latches exhaustion and stops writing the ring when the
live-field distance reaches its capacity. The main task checks the latch before
simulation work and again before replaying controls. It aborts through WHDLoad
with an explanatory message instead of consuming stale controls. An interrupt
during replay cannot overwrite queued history: the producer never writes after
exhaustion. The abort runs outside the interrupt handler.

The default capacity remains 2,048 fields, with a conservative maximum backlog
of 2,047 fields (40.94 seconds at 50 Hz). Below that boundary, all elapsed ticks
are still consumed without resetting time or changing the timestep. Exhaustion
terminates the run; this is an explicit resource-limit failure, not seamless
recovery or a promise of real-time operation on an overloaded CPU.

`STEP_INPUT_SLOTS` permits smaller diagnostic capacities and rejects non-power-
of-two values, capacities below two, or capacities beyond signed word indexing.
`c-input-full-build` uses eight slots and a 16-field presentation interval.
`c-input-full-replay/overflow.png` confirms a clean AmigaDOS return with the
expected message. `c-input-guard-replay` uses the default capacity and matches
all 1,598 completed hashes, the field-1457 actor/clock/camera/rank state and the
three sound requests from `c-events1-replay`. The normal slave is byte-identical.
With the same forced-overflow build but `CUSTOM2=0`, `c-input-full-off` reaches
the race with selection reason 0 and all checked original timing, input, stack
and geometry instructions intact.

## Reset before native race preparation

The first human-to-human race transition exposed a missing reset boundary.
Native initialization clears the game clock at `$8690c`, then `$86616/$8661c`
call the patched race loop and `$86630/$8665c` call the field handler while
preparing display buffers. These calls occur before `$a8c4c`, where C previously
reset its history. A later race therefore used the preceding race's simulation
cursor during preparation. The overflow guard made this visible as an explicit
input-history error in `c-restart-f10` and `c-restart-f10-var`; merely removing
that guard would conceal the stale state.

The selected C patch list now hooks `$8660e` to reset history before preparation,
clear queued controls and clear the cached start pose. Its initial cursor is
live field minus one, reproducing the first boot's initial field-1 step.
The existing reset at interrupt installation remains, establishing the active
race's cursor after preparation. Both paths use the same history-reset helper.
The early hook retains the replaced delta assignment and is under CUSTOM2.

`c-restart-fixed` drives the first race to field 1600, exits with native F10
(raw key `$59`), passes the repair screen with fire, and starts another race.
At its field 100, the cursor is 99, step count 98 and capture flag zero, replacing
the prior race's field-1457 capture. RIGHT produces steering 798 at field 120;
release returns it to zero by field 160. The final screenshot shows the second
race. `c-reset-fixed-regression` preserves all 1,598 original attack-tape hashes,
sound requests and fixed-boundary actor/clock/camera/rank state.
The normal slave remains byte-identical. This covers voluntary race exit and
restart, not crossing the finish line or progression after winning.
`c-reset-fixed-off` verifies that `$8660e` and all other checked timing/input
hooks retain their original instructions when CUSTOM2 is off.

`c-restart-var-settled` repeats the transition with the varying render-period
pattern. The second race again reaches field 100 with cursor 99, 98 steps and
capture flag zero. RIGHT is consumed during catch-up; released steering reaches
zero by live field 200 (cursor 198). An earlier check at live field 160 still had
steering 24 because the cursor was only 154. Live-field checkpoints are not
equal simulation boundaries, so that intermediate difference is not treated as
a state mismatch.

## Stop catch-up at the race-ending tick

`VERIFY_C_SEED_FINISH` is a synthetic boundary fixture: at field 501 it sets
the player's finished flag, finish timestamp and native finish-countdown state.
It does not set the race-exit request or shorten the countdown. Native action
code at `$90252` calls `$8f136`; the ten countdown increments request exit at
field 690. This fixture does not cover naturally crossing the finish line.

Before the correction, `c-finish1-before` and `c-finishvar-before` both capture
the exit flag already set at field 690 but continue through field 691. The
native outer loop consequently records 691 in `$a5d54`. C now checks the exit
request before starting another simulation step, publishes the final state
through the existing rendering path, and lets the native outer loop leave.
Elapsed time after a terminal race state does not authorize further gameplay.

`c-finish1-fixed` and `c-finishvar-fixed` both stop at cursor 690, with 689
completed active-race steps (the active cursor starts at field 1), finish timestamp
501 and end timestamp 690. All completed hashes match across cadences and match
the corresponding pre-fix prefixes. The frozen field-690 actor, stopwatch,
simulation clock, camera, crash-camera and rank state also matches. The native
finish counter reaches ten and the race interrupt hook is cleared in both runs.
The test does not establish winning progression or audible end-of-race sound.
With the fixture disabled, `c-finish-regression` retains all 1,598 attack/crash
tape hashes, sound requests and the field-1457 comparison state from
`c-reset-fixed-regression`. The normal slave binary remains unchanged.

## Full race through the actual finish line

`STEP_CAPTURE_END` optionally captures the final simulation step when the native
exit request is set, publishing its actual cursor in the existing capture field.
This permits equal-boundary comparisons without predicting the race duration.
With the option absent, `c-endcapture-disabled-build` is byte-identical to
`c-finish-disabled-build`; the normal slave is also unchanged.

`c-fullrace1` uses ordinary controls throughout a complete race. A host driver
follows the road, releases controls during crashes, and resumes after remounting.
It records 148 input changes at exact field boundaries. No game state, finish
flag, timer or course length is injected. The original finish coordinate is
1855; the player crosses it at simulation field 13835, finishes in rank 4, and
the native countdown ends the race at 14024. This includes continued racing
after the earlier crash/recovery scenario and additional later crashes.

`c-fullracevar` replays those exact recorded inputs with varying render
intervals. All 14,023 completed active-race hashes match, including six complete
wraps of the 2,048-slot hash ring. All 52 traced sound requests match: seven
engine/crash starts, seven stops and 38 primary effects. Neither event log
overflows. Both runs have finish timestamp 13835 and end timestamp 14024;
the terminal actor records, stopwatch, simulation clock, camera, crash-camera
offset and rank cells match exactly.

The varying-cadence run also passes the post-race screens with fire and starts
another human race. At live field 100 its cursor is 98, step count 97 and capture
flag zero; the finish flag is clear. `next-race.png` shows the new race.
This establishes actual finish-line and post-race restart coverage for this
route. It does not cover every championship outcome or audible sound playback.
The private evidence and recorded tape are under `tmp/dev/tmp/c-fullrace1` and
`tmp/dev/tmp/c-fullracevar`.

## Shared runtime integration

`simulation.s` now contains the shared C implementation formerly in
`verify_c_step.s`. Normal builds include it with `C_RUNTIME_ONLY`, omitting the
large frozen snapshot, hash array and per-step hashing. They retain the small
cursor/counter record used by scheduling and the input ring. `VERIFY` builds
retain the earlier A/B path unless `VERIFY_C_STEP` selects the full C diagnostic;
`C_SIMULATION` explicitly selects the lean runtime with optional generic
instrumentation. None of these build switches is a user-facing frame-rate mode.

The normal beta is 6,584 bytes and is byte-identical to the private runtime
prototype used for steering/release and keyboard pause/resume checks
(`c-runtime-prototype-input`). Pause freezes the active clock at field 161.
The full C diagnostic built after extraction is byte-identical to
`c-endcapture-disabled-build`, retaining the earlier regression implementation.

`c-runtime-boundary` runs the actual normal slave with the attack/crash tape,
then breaks immediately before returning from the completed simulation step.
At cursor 1457, all actor records, stopwatch, simulation clock, camera,
crash-camera offset and rank cells match the diagnostic capture in
`c-finish-regression`. The runtime binary contains no capture instrumentation;
the debugger reads the authoritative state at that boundary.

`c-runtime-dispatch` verifies the actual normal slave in five configurations:
toggle omitted, toggle explicitly off, enabled with 68020/Fast RAM, enabled on
the 1 MB Chip 68000 setup, and enabled on a Chip-only 68020. Both off cases and
both unsupported configurations retain the original preparation, simulation,
delta, animation, swap, input and camera instructions. The supported machine
installs C and advances one-field simulation steps. The normal Readme and build
dependencies now describe this integration. Broader A2/A4, MMU, CD32 and latency
validation remains required before declaring C complete.

## Integrated runtime hardware matrix

`c-runtime-matrix-low` and `c-runtime-matrix-high` exercise all 13 A2 cells with
the lean runtime plus generic field/frame counters and the MMU-register probe.
Each cell has a 240-second deadline. All complete the route and measurement
window; both explicit MMU configurations report TC `$8000`. Those two cells are
functional checks only, and the existing 040/060 emulator timing limitations
still apply.

| Cell | B reference fps | C measured fps | Distance change vs B |
|---|---:|---:|---:|
| A500 1 MB Chip | 8.5 | 8.5 | -1.70% |
| A1200 Chip only | 12.5 | 12.5 | 0.00% |
| A1200 Fast | 12.5 | 1.8 | -1.66% |
| A1200 Fast + Cache | 16.5 | 4.9 | -0.42% |
| A1200 Fast + NoCache | 12.5 | 1.8 | -1.66% |
| 030/50 | 13.3 | 4.4 | -1.28% |
| 030/50 + Cache | 16.6 | 9.0 | -0.99% |
| 040/25 | 22.5 | 12.5 | -1.28% |
| 040/25 + Cache | 22.5 | 12.5 | -1.28% |
| 060/50 | 23.1 | 13.7 | -0.52% |
| 060/50 + Cache | 23.1 | 13.7 | -0.52% |

The B reference is `b-final-matrix-v2`; the window is 500 active fields after
field 100, with distance measured after 490 fields. JSON evidence retains the
frame histograms, CPU/cache settings and screenshots. These are **functional
passes, not a performance or A4 pass**. The new simulation consumes appreciably
more CPU time and several live-field distance comparisons exceed 1%. C must
remain open; the integrated beta is not evidence of an achieved speedup.

The A500 distance discrepancy is an instrumentation effect: the actual normal
slave in `c-runtime-normal-a500` matches `b-final-normal-off` exactly at 8.5 fps
and distance 3,425,028, including initial, field-590 and final actor/clock/rank
hashes. The unsupported path retains native game instructions.
`c-runtime-cd32` also passes steering/release and CD32 pause/resume on the actual
normal slave, holding the active field clock at 161 while paused.

The cached-020 field-590 screenshots show the same road scene and player off the
right edge, but differ in displayed road/scenery and opponent details. A completed
tick-1457 comparison between functional and real-speed runs likewise matches
player movement, stopwatch, camera and rank cells but differs in some opponents
and the random spawn timer at `$a5d5c`. This is not yet a proven CPU-dependent
simulation defect: the native menu calls all three random generators at
`$8187a..$81886`, so matching race inputs does not establish matching RNG state.
The prior six-byte “clock” comparison also includes `$a5d5c`; only
`$a5d58..$a5d5b` is the stopwatch.

`VERIFY_C_SEED_RNG` provides controlled diagnostic initial conditions by calling
the native seed routines `$90088` (table generator, seed zero) and `$9011c`
before native race initialization at `$8657c`. Seeding after actors have spawned
would be too late. The switch requires VERIFY and does not alter the normal
binary or normal-game randomness. New cross-speed probes record the initial
RNG table/cursors as well as the initial actor state.

`c-runtime-seeded-functional` and `c-runtime-seeded-real020` have identical RNG
tables/cursors at live field 100. Their initial live snapshots are not equivalent
simulation boundaries (cursors 99 and 97), so those actor snapshots are not used
as an equality assertion. At the completed tick-1457 breakpoint, however, every
actor byte, stopwatch, spawn timer, simulation clock, camera, crash-camera offset
and rank cell matches exactly. For this scenario, the earlier opponent
differences are resolved by controlled initial randomness; they are not evidence
of a different result from the same seeded simulation at the two CPU speeds.
This does not remove the measured throughput regression or close the outstanding
performance and latency work.

## Fast RAM stack enabled in the runtime

The previously tested stack experiment is now enabled in `C_RUNTIME_ONLY`
builds as `C_FAST_STACK`, sharing `runtime_stack.s` with the diagnostic
`VERIFY_C_FAST_STACK` opt-in. WHDLoad reserves an optional 20 KiB expansion block;
16 KiB is used for the CPU stack with guards at both ends. The selected C path
switches at the original trap-2 stack setup while interrupts are masked. It
does not copy an active frame, and retains the original Chip stack if the block
is absent or outside the supported Fast RAM windows. The master toggle and
hardware selector still control installation of the stack hook. The optional
reservation is declared in the slave header, before the toggle is read; an
off-toggle run never switches to it.

The normal slave is 6,744 bytes. `c-stack-matrix-low/high` repeats all 13 A2 cells
with the same 500-field window and limits as the preceding runtime matrix.
Every cell completes, including both explicit MMU cases. Measured changes:

| Configuration | Previous C fps | Fast-stack C fps |
|---|---:|---:|
| A1200 Fast / explicit NoCache | 1.8 | 3.5 |
| A1200 Fast + Cache | 4.9 | 6.8 |
| 030/50 | 4.4 | 6.1 |
| 030/50 + Cache | 9.0 | 12.5 |
| 040/25, with or without Cache | 12.5 | 16.6 |
| 060/50, with or without Cache | 13.7 | 18.3 |

A500 and Chip-only A1200 fallback rates remain 8.5 and 12.5 fps respectively.
These gains do not yet recover the earlier B rendering throughput. The stack
removes a measured source of CPU/Chip-bus cost; it does not change simulation
steps, discard elapsed time, or add pacing.

`c-runtime-stack-seeded-boundary` matches all compared actor, clock, spawn-timer,
camera and rank state at completed tick 1457 against the previous controlled-
seed real-speed 020 runtime. `c-runtime-stack-cd32` passes steering and CD32
pause/resume on the actual normal binary, with 336 bytes of observed stack use
and both guards intact. `c-runtime-stack-off` confirms the normal binary retains
native stack setup and all checked original timing/input hooks with CUSTOM2=0.

`c-runtime-stack-040-quit` and `c-runtime-stack-060-z3-quit` verify TC `$8000`,
intact stack guards and 204 bytes of observed stack use, then press the actual
Help quit key. Both inspected screenshots show return to AmigaDOS without an
error. The 060 case uses Z3 RAM, with stack bottom `$407ed010`. These are bounded
observations, not proof of a universal worst-case stack bound. Remaining
throughput, A4 and latency validation stays open.

## Reuse simulation-owned actor lean

The actor pose loop at `$89e70..$89eec` repeated the lean calculation already
performed by `step_derive_lean`, including a division and threshold-table walk.
Its result was discarded: C suppresses the native actor `+$34` store, and the
pose selectors read the stored simulation lean. The enhanced patch now enters
`step_lean_end` directly from that presentation entry. The authoritative pass
executes the displaced subtraction and enters the original calculation at
`$89e76`. Native visibility tests, pose side effects and projection remain.
The hook belongs to the same CUSTOM2-gated C patch list.

Validation in the private harness:

- `c-lean-attacks` matches all 1,598 common completed actor hashes and all sound
  events against `c-finish-regression`. The entire tick-1457 snapshot and final
  screenshot pixels match too.
- `c-lean-fullrace` replays the recorded full race: all 14,023 hashes, 52 sound
  events, finish and exit times match `c-fullrace1`. Final actor, clock,
  spawn-timer, camera and rank ranges match. Presentation scratch data and the
  asynchronous final image differ; this is not a full-snapshot equality claim.
  The inspected finish and next-race images render correctly, and the next race
  resets the capture and simulation counters.
- `c-lean-armedvar` matches 1,597 common hashes, all sound requests and the same
  authoritative snapshot ranges against the earlier varying-cadence armed
  fixture, including secondary sound requests.
- `c-lean-runtime-matrix`, using the explicit runtime binary, measures 7.1 fps
  on cached A1200 Fast (previous Fast-stack C: 6.8) and 12.5 on cached 030/50
  (unchanged), over the same 500-field window. This small improvement does not
  resolve the remaining throughput regression or establish latency acceptance.
- `c-lean-off` checks the actual normal slave with CUSTOM2=0: the new lean
  entry and all previously checked timing, input and stack sites remain native.

The normal slave is now 6,768 bytes. This change leaves C open.

## Project forward actors only for presentation

The forward actor path finishes pose selection and its attack/sound side
effects before `$89f48`. From that point it builds depth and screen records,
clips them and appends crash, rider and spark visuals. Those helpers write
presentation records and counts; C already owns spark lifetime separately.
`step_pose_project` now returns to the next actor during `step_pose_events`.
During rendering it executes the displaced position subtraction and continues
the original projection path. The rear-view path is unchanged.

This does not remove the world-object projection used for collisions:
`step_collision_objects` still rebuilds those inputs before every simulation
tick. Nor does it bypass the earlier pose eligibility checks or state changes.
The new patch is inside the existing CUSTOM2/hardware-selected patch list.

`c-pose-project-fullrace` matches all 14,023 completed hashes, all 52 sound
requests and the original finish/exit boundaries against `c-fullrace1`. Final
actor, clock, spawn-timer, camera and rank ranges match. Starting the next race
resets simulation and capture state. `c-pose-project-armedvar` matches all
1,596 common hashes, sound requests and those authoritative snapshot ranges
against the earlier varying-cadence armed fixture. Inspected finish, next-race
and armed-fixture screenshots render correctly; presentation scratch buffers
are intentionally not compared for byte equality.

The explicit runtime build in `c-pose-project-matrix` measures 8.7 fps on cached
A1200 Fast, up from 7.1 after lean reuse. Cached 030/50 remains 12.5 fps; 040/25
is 16.6 and 060/50 is 18.5. These are the existing 500-field measurements, not
50 fps or B-throughput acceptance. `c-pose-project-pad` passes actual normal
binary steering/release and CD32 pause/resume with intact stack guards.
`c-pose-project-off` confirms that CUSTOM2=0 leaves the projection entry and all
other checked enhanced hook sites native. The normal slave is 6,804 bytes.

`c-pose-project-fullvar` repeats the complete tape with varying presentation
intervals (2, 3, 4, 12 and 16 fields). All 14,023 hashes, 52 events, terminal
boundaries and the authoritative snapshot ranges match the original full-race
reference too.

`c-pose-project-latency-a1200-fast+cache` uses the runtime with only the optional
latency probe added. For RIGHT injected after field 300, input is captured and
replayed at 301, its simulation finishes at live field 302, rendering starts
at 302, swap is entered at 304 and returns at 305. That is 100 ms from injection
to buffer handoff. This one phase is not a latency distribution or a measurement
of the first changed scanout pixels; it does not close C3b. Performance, A4 and
latency acceptance remain open.

## Visible steering response: a remaining simulation regression

The buffer-handoff probe does not establish when steering first becomes visible.
`visible_latency_c.py` and `visible_latency_batch_c.py` now compare paired normal
binary runs on the real-speed cached A1200 Fast configuration. Each pair reaches
the same race field with identical initial snapshot hashes; both hold throttle
from field 100, then one adds RIGHT and the other stays neutral. Eight pairs per
binary inject at fields 300 through 307. The B reference is the preserved
`b-final-build/RoadRash.slave`, with its validated `Cache CUSTOM2=3` settings;
C uses the current normal binary with `Cache CUSTOM2=1`. Neither has timing
probes or per-tick hashes compiled in.

Twenty consecutive profiler screenshots are retained per run. The capture
advances 21 active fields; image labels are assigned backwards from that end
boundary. The table reports capture-end estimates with one PAL field of boundary
uncertainty, not host-display latency or an exact scanline timestamp. Within each
pair, the road viewport is pixel-identical until the first differing image.
The inspected first differences are the player's steering pose, rather than a
HUD clock change. Initial state and effective configuration equality are checked
within each pair; B and C do not have identical simulation histories.

| Input field | B first-visible estimate (ms) | C first-visible estimate (ms) |
|---:|---:|---:|
| 300 | 180 | 360 |
| 301 | 220 | 340 |
| 302 | 200 | 420 |
| 303 | 180 | 400 |
| 304 | 220 | 380 |
| 305 | 200 | 360 |
| 306 | 180 | 340 |
| 307 | 220 | 420 |

These are eight consecutive phases of one low-speed steering scenario, not a
general latency distribution. Their medians are 200 and 370 ms respectively.
The gap is substantially larger than the capture-boundary uncertainty. Evidence
is in `b-visible-phases`, `c-visible-phases`, and the reused C field-300 pilot
pair. Tested slave SHA-256 values are
`6892f327f8f6c7719a3d5603a4bd1ed6a844dbd228b7e50c916678d58ba10bf3` (B) and
`fc07ed239f111fb376dc0101fabffee2dd42bd779190df73c87b1a8cdc16e7cf` (C).

Retained instruction traces in `b-visible-steering-trace` and
`c-visible-steering-trace` explain why presentation scheduling alone is not
enough. Native player steering at `$8b93a` starts with actor `+$26` (speed times
elapsed fields), shifts it by eight, multiplies by steering `+$42`, then shifts
again at `$8b946`. The resulting integer is stored in `+$0c` and normally `+$08`.
Later `$8b97a..$8b97c` multiplies by that elapsed-movement factor again before
another shift and the `$d000` scale. Small one-field results round away.

For field-300 input, C's first captured movement factor is 25; B's is 76 with a
three-field native update. At the end of the 20-image capture (live field 321),
C has `+$08=6`, `+$22=0`, and lateral position `+$00=160`; B has `+$08=21`,
`+$22=4`, and `+$00=174`. Both start at 160, with similar speeds (6446 and 6454).
The traces and player records are retained alongside reduced `steering-math.json`.
This demonstrates lost small movement in C; it does not assign the entire
visible-response gap to rounding, since frame throughput also differs.

C1b therefore still needs steering/displacement normalization and fractional
remainder handling, with the camera, tyre-grip and pose consumers audited too.
Simply amplifying input or changing the simulation quantum would not establish
correct behavior. Any correction needs fresh cross-cadence state/event replays,
B handling comparisons and these visible-response checks. Existing identical
C replay hashes prove determinism, not correct handling relative to B.

## Diagnostic steering normalization candidate

`VERIFY_C_STEERING` includes `verify_c_steering.s`, requires VERIFY and
`STEP_FIELDS=1`, and installs its hooks only through the selected C patch list.
It is not enabled in the normal build. The normal slave remains byte-identical
to `a2eb36e` (6,804 bytes).

The candidate separates two native uses of elapsed movement:

- For a riding player, the initial heading/pose calculation uses speed times
  the established four-field timing reference. Its second movement factor stays
  one-field distance. Crashing players retain the native initial calculation.
- For non-skidding ground movement, the two truncations `/256` and `*13/16`
  become one signed rational calculation with denominator 4096. The residual
  is carried to the next tick, with symmetric truncation toward zero.
  Native skid scaling remains in place and clears the residual; crash handling
  clears it too. The normalized heading still feeds the native grip test, so
  retaining its code does not prove identical skid behavior.
- Race preparation and active-race reset clear the residual. Airborne movement
  bypasses this native ground path; landing and collision/reset interactions
  still need explicit validation.

On the field-300 real-speed cached-020 paired-image test,
`c-steering-candidate-0/1`, the first differing viewport capture is field 311
(220 ms capture-end estimate), versus field 318 (360 ms) in the current normal
C binary. This is a diagnostic-build, single-phase observation, not a new
normal-runtime latency claim. At live field 321, the candidate has player
position 179, heading 25 and last lateral increment 2; the current normal C
has position 160, heading 6 and increment 0. The earlier B three-field sample
has position 174, heading 21 and increment 4.

The controlled B-style four-field diagnostic
`b-steering-fourfield-trace` ends at position 187, heading 30 and increment 10.
It starts with speed 6480 and ends at 7104, whereas the candidate starts at
6420 and ends at 6966. These live-field snapshots are not equal simulation
boundaries and do not establish calibrated trajectory equivalence. They are a
reason to continue the reference comparison, not to promote the candidate.

The retained candidate RIGHT and LEFT traces each provide 20 ground-path
returns. Every observed `$8b9a0` result matches an independent calculation of
`trunc((13 * signed_product + previous_remainder) / 4096)`; final remainders
are 3556 and -3345. The LEFT sample ends at position 138 and heading -28.
The carry is symmetric, but the earlier native input/heading truncations and
input history are not thereby proved symmetric.

`c-steering-candidate-replay` and `c-steering-candidate-var` replay the attack
tape with ordinary and varying presentation cadence. All 1,598 completed actor
hashes, three sound requests, and tick-1457 actor/clock/spawn-timer/camera/rank
ranges match between the two candidate runs. The candidate intentionally
differs from the old C state; cross-cadence equality alone is not acceptance.
Full-race, skid/crash/landing, pause/restart, curve/AI interactions, signed
handling calibration and multi-phase visible-response checks remain required.

## Steering candidate: full-race and phase coverage

`c-steering-fullrace` drives a complete race using ordinary controls and records
the input tape. `c-steering-fullvar` replays it with varying render intervals.
All 11,990 completed actor hashes, 35 sound events, finish tick 11802, end tick
11991 and terminal actor/clock/spawn-timer/camera/rank ranges match. Both start
another race with reset simulation/capture state. Finish and next-race images
were inspected. This compares the candidate against itself across presentation
cadences, not against the previous C race with different controls.

The variable replay samples player state every 20 fields: 595 samples include
15 with the skid flag, 12 airborne, and crash states 0, 1, 2, 3 and 4 followed
by riding again. Remainders stay between -4056 and 4080. The samples expose a
cleanup hole: airborne crash states bypass the ground-motion hook, retaining
remainders such as 2434 through fields 2200–2260. The candidate now calls
`step_steering_finish` at the completed simulation boundary, clearing residual
ground movement whenever the player is crashing. Native ground-path clearing
alone was insufficient.

Before that cleanup, `c-steering-visible-phases` completed the same eight
paired visible-response scenarios as the B/normal-C audit:

| Input field | Candidate first-visible estimate (ms) |
|---:|---:|
| 300 | 220 |
| 301 | 200 |
| 302 | 180 |
| 303 | 260 |
| 304 | 240 |
| 305 | 220 |
| 306 | 200 |
| 307 | 180 |

The median is 210 ms, compared with B's 200 and uncorrected normal C's 370.
The same one-field capture-boundary uncertainty applies. These remain
diagnostic-build measurements in one low-speed scenario, not a general latency
pass for the normal runtime or for the subsequent cleanup build.

`c-steering-candidate-pad` passes steering/release and CD32 pause/resume on
real-speed cached 020, with the clock frozen at field 161 while paused.
Fast-stack guards remain intact, with 332 bytes of observed use.

The native input routine itself explains one source of left/right asymmetry:
`$872d2..$872e0` gives LEFT a reversal increment when starting from zero,
whereas `$87310..$8731e` omits it for RIGHT at zero. The candidate preserves
that existing behavior; symmetric fractional carry does not make the entire
control response symmetric.

`c-steering-reset-fullvar` validates the boundary cleanup on the full recorded
tape: all 11,990 hashes, 35 sound events, finish/exit boundaries and authoritative
terminal ranges still match `c-steering-fullrace`. All 38 sampled crash states
now have a zero fractional remainder. The next race starts with reset counters.
The normal binary remains byte-identical; this closes the observed candidate
cleanup defect, not the outstanding B handling calibration or normal-runtime
integration and acceptance checks.

## Shared seeded B/C handling calibration

`VERIFY_C_SEED_RNG` now installs its existing initializer through `pl_main`,
still behind CUSTOM2 and still diagnostic-only. Its code is shared by B-style
VERIFY builds and C, so a native timing reference can start from the same
random state as the candidate. The normal slave remains byte-identical.

`b-steering-seeded-lap`, `b-fourfield-seeded-lap` and
`c-steering-seeded-lap` use cached real-speed 020, the established A1 tape and
the same initializer. All three live-field-100 additive RNG snapshots
(`$90000..$90087`) have SHA-256
`c28968215eeea324c122f851f13d71f1658b9668d801360bef88d4c632bf3dec`.
This controls the initial randomness; it does not equate their simulation
boundaries or subsequent random consumption.

The comparison identifies a candidate handling defect independent of that
randomness: before steering begins at field 600, both B references retain
player lateral position 160, whereas the candidate reaches 183. The
unseeded replay showed the same effect. This is why the earlier full-race
cross-cadence pass and better response time were insufficient for promotion.

## Retain native reference rounding in steering

The neutral-input traces `c-neutral-base-trace` and
`c-neutral-candidate-trace` isolate the drift. At field 440 both have steering
`+$42=0`, heading `+$08=0`, road centre `+$36=-9` and road fraction `+$38=-1`.
The native signed-word multiplication at `$8b97a` consequently multiplies 36
by 1. The original two rounding stages discard that displacement. The previous
candidate instead accumulates it, moving from lateral position 161 to 164
during the 20-image capture while the original C path stays at 160.

A temporary zero-steering guard removed that drift, but the
`c-steering-neutralfix-lap` still oversteered the first pulse (237 at field 700
versus the four-field reference's 215). The committed diagnostic model therefore
supersedes the earlier combined `/4096` carry:

- Both movement factors use the four-field reference for a riding player.
- The original integer `/256`, tyre-grip path and `$d000` scale run unchanged
  on that reference displacement.
- A new hook at `$8b9a0` integrates one quarter of the resulting signed integer
  per simulation tick, carrying only the quarter-unit remainder (-3 through 3).
  It does not resurrect road fractions that the native reference discarded.
- Crashing/airborne players keep their native displacement path, clearing the
  remainder. The completed-tick crash cleanup remains in place for bypasses.

`c-steering-reference-lap` uses the same seed and tape as
`b-fourfield-seeded-lap`. It remains at lateral position 160 until steering starts.
The first-pulse checkpoints are now 214 versus 215 at field 700, and 194 versus
192 at field 800. Later trajectories still diverge: sampled crash onset is 1442
versus 1350. Both have one crash and final rank 21, but complete opponent order
and image equality fail. The retained `a4-comparison.json` explicitly reports
that failure; this is improved calibration, not A4 acceptance.

The seeded `c-steering-reference-replay/var` pair matches all 1,596 common
completed hashes, three sound requests, and tick-1457 authoritative ranges.
These tests cover the revised model; the earlier full-race and eight-phase
latency results describe its predecessor and must not be claimed for this model.

The RIGHT and LEFT traces each validate 20 writes against an independent
signed quarter-displacement calculation; final remainders are 2 and -2.
`c-steering-reference-distance` measures 8.5 fps and distance 3,318,164 over the
standard window, versus seeded B's 3,374,076. The -1.657% difference fails A4a.
This live-field comparison includes different simulation/render progress and
does not by itself identify the cause. The normal 6,804-byte slave is unchanged.

## Completed-step distance accounting

`b-reference-distance-boundaries` and `c-reference-distance-boundaries` repeat
seeded cached-020 throttle input at live field 100. They stop at every completed
logic step (B's `$875b6`, C's final `step_end` RTS), recording live field,
simulation cursor, position, speed and applied delta. Debugger stops do not
advance emulated time. C records 501 completions through live field 600; B
records 166 through live field 602. These are the same candidate/reference
binaries used for the preceding distance comparison.

At completed cursor 590, B's position is 3,898,364 and C's is 3,852,194.
Relative to the initial 524,288, C remains 1.368% behind. C completes that tick
at live field 593. Thus render debt explains only part of the earlier 1.657%
live-field difference; it is not sufficient to explain away the A4 failure.

The B trace also sums to 492 applied fields after the live-field-100 input,
although its cursor advances to 590. Its first completed step, at cursor 101,
already applies delta 3, reaching speed 102. C's cursor-101 step applies one
field, reaching speed 34. B applies the sampled throttle to a whole native
multi-field step. Its cursor labels alone do not measure the integrated time
following this input; the native delta can also lag the current render interval.

At C cursor 592 (492 applied throttle fields), position is 3,871,631: a 0.792%
distance difference from B's 492-field result. This is a diagnostic time-aligned
comparison, not a replacement for the A4 live-field acceptance window. Every B
position increment in the measured window equals its end-of-step speed times
its delta. Splitting those same B speed changes linearly into unit steps would
remove 10,161 distance units of endpoint-integration bias; another 16,572 units
remain relative to C. That calculation does not equate gear, terrain or other
state-dependent decisions across the two paths. No compensating speed multiplier
or extra simulation time has been introduced. Raw steps and the derived figures
are retained in `c-reference-distance-boundaries/comparison.json`; C remains open.

## Revised steering: visible response and race-exit replay

`c-steering-reference-visible-phases` measures the revised quarter-displacement
candidate, using fresh neutral/RIGHT pairs for all eight injection fields 300–307.
Within each pair the initial snapshots match exactly. First changed race-view
captures give upper estimates of 260, 240, 220, 200, 180, 260, 240 and 220 ms,
median 230 ms. The field-300 difference image includes the rider and road view.
These remain capture-end estimates with one-field uncertainty, not hardware
input-to-monitor latency. The corresponding retained B median is 200 ms and
uncorrected C median is 370 ms. The new candidate substantially improves response
but does not eliminate the regression against B. Its predecessor's 210 ms
median does not describe this revised model.

`c-steering-quarter-fullrace` drives the current model using ordinary adaptive
controls, recording the resulting input tape. It publishes 11,945 completed
step hashes, then exits at simulation field 11946 after bike damage; `finish=0`.
This is a wreck/exit test, not proof of successful race completion. It records
120 sound requests and starts another race with capture state `(99,98,0,1)`.
Of 593 samples, three have skid flags and 19 are airborne; all five crash states
occur, with zero residual in all 97 sampled crash states. Every sampled steering
residual stays strictly between -4 and 4. Sampling every 20 fields does not
prove every intermediate state. The normal slave remains unchanged, SHA-256
`fc07ed239f111fb376dc0101fabffee2dd42bd779190df73c87b1a8cdc16e7cf`.

`c-steering-quarter-fullvar` replays that exact tape with the existing
2/3/4/12/16-field render pattern. All 11,945 hashes and all 120 sound requests
match, as do terminal capture fields and the actor, clock/spawn-timer, camera
and rank ranges recorded in its `comparison.json`. Both runs restart with the
same cleared capture state. This establishes render-cadence independence for
the revised model through the tested wreck and restart; successful finish-line
coverage for this model, remaining A4 differences and the latency/performance
regressions are still open.

## Defer width division until after object rejection

`VERIFY_C_OBJECT_WIDTH` is a diagnostic-only C patch under the same CUSTOM2 and
hardware gates. It replaces the divide/store at `$8b2e8` with NOPs and performs
those operations at `$8b326`, after the native depth/lateral rejection tests.
The numerator D3 and divisor D1 remain unchanged through that interval. Accepted
records receive the same width before D3 is reused for height at `$8b332`;
rejected records are not published. The hook restores the displaced `add.w d2,d2`
and `lea $a7068,a2`. It neither removes the collision projection pass nor changes
its visibility decisions. Normal builds remain byte-identical.

`c-object-width-replay1457` matches all 1,598 common hashes, sound requests and
the entire captured `$a5900..$a873f` state against
`c-steering-reference-replay`. The first attempted replay build mistakenly used
the default capture field 601; the harness correctly rejected it rather than
comparing it with field 1457. Only the rebuilt 1457 run is acceptance evidence.

On cycle-exact cached 020, the standard 500-field window measures 8.7 fps versus
8.5 for the unchanged steering candidate. The longer paired cost runs
`c-object-width-baseline-cost` and `c-object-width-cost` show 177 versus 179
renders over fields 100–1000 (9.833 versus 9.944 fps, about 1.13%). Their sampled
simulation cursor/count and position agree at every checkpoint. This is a small
workload-specific gain, not resolution of C's throughput regression, and the
experiment is not yet enabled in the normal slave.

`c-object-width-fullvar` also matches all 11,945 completed hashes and 120 sound
requests against `c-steering-quarter-fullrace` while replaying its tape under
varying render intervals. The terminal actor, clock/spawn-timer, camera and rank
ranges match, as do exit field 11946 and restart capture `(99,98,0,1)`. This
extends the experiment's equivalence evidence through crashes, wreck and restart.
