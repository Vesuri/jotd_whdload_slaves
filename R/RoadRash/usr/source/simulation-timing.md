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

`$8eff8`, called among rendering preparation at `$876c6`, consumes sound-event flags,
decrements `$a5d5e` using delta, and clears `$a598a/$a598b`. It must consume each
simulation step's events once, including intermediate catch-up steps. The audio
sequencer and music interrupts remain on their existing field/timer clocks.

## Direct delta references

The captured program disassembly contains **39 direct references** to `$a6f00`:
five writes, one zero check, and 33 consumers. This inventory does not rule out
indirect aliases or other frame-dependent updates.

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
