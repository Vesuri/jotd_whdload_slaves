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
Moving this call to a 50 Hz simulation does not by itself preserve its decay rate:
four calls leave approximately `(3/4)^4 = 31.6%` of the offset, whereas the
four-field original reference leaves 75%. The movement integration reads the
delta-scaled actor displacement, but the decay needs explicit elapsed-time
normalization. This remains open; cross-render-rate hashes cannot detect it.

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
simulation on 68020+ with Fast RAM. CPU and memory detection and production
dispatch remain to be implemented; these experiments do not change the normal
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
