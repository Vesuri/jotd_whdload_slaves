# Track-height projection investigation (H1)

**Follow-up, 2026-10-22:** the user subsequently authorized fixing these inherited
bugs in both framerate modes. [Implementation and validation](visual-fixes.md)
supersede the historical no-patch/evaluation-only disposition below.


Completed 2026-10-21. H1c is an evaluation only, as requested: no correction
has been applied to the slave, release archive or running game.

## Finding

The vertical discontinuity is inherited from the original road projection.
It reproduces in untouched v2.0, 3.0b with CUSTOM2 off, and 3.0b with CUSTOM2 on.
The fractional camera-height offset uses one track interval's height change,
while the road points ahead use the following interval's height change.
Crossing a segment boundary changes the height reference abruptly whenever
those two values differ. Both the road and the player are projected from that
reference, explaining their synchronized movement.

The enhancement does not amplify this calculation at an identical camera,
track and actor state. Higher rendering cadence samples more phases of the
existing discontinuity. This finding does not assert equal perceived severity
or identical trajectories between the native and enhanced simulation paths.

The 50 recording frames at 64.012–64.987 s in
`Screen Recording 2026-10-21 at 23.14.20.mov` show the reported rising/drop
pattern, including a 79-recording-pixel drop from frame 10 to 11. The recording
has no game-state/input trace, so its exact frame pair has not been replayed.
The controlled captures reproduce the mechanism and its larger magnitude on
later hills, rather than treating the earlier small first-hill jumps alone as
proof of the larger reported event.

## H1a: matched hills and consecutive render captures

All runs used an isolated deterministic 68040/25 MHz AGA emulator, 2 MiB Chip,
8 MiB Fast, PRELOAD and WHDLoad `Cache`. The passive debugger's data-cache
emulation was disabled; these are projection tests, not hardware cache tests.
No game-memory writes or synthetic actor states were used in the emulator.

The probe stops at `$87670`, immediately after actor projection. It records the
current 256-entry track table, camera/player state, all 32 geometric height
values, all 32 projected road Y values, and actor draw records. Track data is
captured per frame because later track sections replace entries in the table.

| Build/path | First-hill render samples | Longer-run samples | Last race field |
| --- | ---: | ---: | ---: |
| 3.0b CUSTOM2=1 | 196 | 3,337 | 3800 |
| 3.0b CUSTOM2=0 | 91 | 1,530 | 3801 |
| Untouched v2.0 | 91 | 1,549 | 3800 |

First-hill runs hold throttle from field 100 and capture fields 400–600.
Longer runs use the same steering controller in each build: aim for lateral
position zero with a 64-unit dead zone, updating at render stops at least 20
fields apart. Comparisons match track sections, not wall-clock screenshots or
identical input tapes. The routes and frame sampling differ between builds.

A model of the native integer operations exactly reproduces the geometric
height table, projected road Y table, and player draw Y in **all 6,794 captured
render snapshots**. This includes signed rounding, the original positive road
Y word overflow, airborne height, and the native speed-bit bobbing adjustment.
Model checks use assertions against the captured game output, not just visual
resemblance.

Examples at matched segment crossings (Y increases downward):

| Crossing | Build | Consecutive race fields | Native player Y | Evaluated Y, same states |
| --- | --- | --- | --- | --- |
| 45 → 46 | enhanced | 510 → 511 | 135 → 138 | 138 → 138 |
| 45 → 46 | option off | 510 → 512 | 136 → 138 | 138 → 138 |
| 45 → 46 | v2.0 | 509 → 512 | 136 → 138 | 138 → 138 |
| 381 → 382 | enhanced | 2378 → 2379 | 116 → 126 | 124 → 126 |
| 381 → 382 | option off | 2350 → 2352 | 116 → 126 | 124 → 126 |
| 381 → 382 | v2.0 | 2355 → 2357 | 116 → 126 | 125 → 125 |
| 583 → 584 | enhanced | 3496 → 3497 | 120 → 131 | 130 → 130 |

These are consecutive rendered states, not necessarily consecutive PAL fields.
The candidate column is an offline reevaluation of those exact states, not
screenshots from a patched game. Ordinary hill motion, integer rounding and
native bobbing remain; the objective is not to pin the rider to one screen Y.

## H1b: exact calculation and boundary error

The native camera setup at `$89138..$8929c` supplies the camera position and
height. In normal grounded play, the camera is half a segment behind the player
and its height is 93. The road generator `$8970e..$898e1` then:

1. Reads the height-change byte for camera segment S at `$89794`.
2. Multiplies it by the fractional position f at `$897a6..$897c6`, truncating
   toward zero, to initialize the vertical accumulator.
3. Adds height-change bytes starting at S+1 at `$898b2..$898c6` while producing
   successive road points.

Ignoring integer rounding, the geometric height numerator for point j is:

```
H(S, f, j) = camera_height + height_change[S] * f
            - sum(height_change[S+k], k=1..j)
```

At a camera boundary, the same world point moves from table index j+1 to j.
Comparing f approaching 1 with the following segment at f=0 gives a jump of:

```
height_change[S+1] - height_change[S]
```

The road uses this table at `$897e6..$89818`. Actor projection at
`$8a764..$8a7d0` interpolates the same table and subtracts actor airborne height.
For the grounded player at the usual half-segment camera offset, the vertical
projection scale is approximately 256/384, so the screen jump is roughly
two-thirds of the height-change mismatch, before integer rounding and motion.
For example, segment 396 has changes -41 and -16: that is a 25-unit reference
error, large enough to explain jumps of the reported order at recording scale.

The native instructions and the same numerical output survive both CUSTOM2
paths. Heading extrapolation does not enter this calculation. Camera or rider
height extrapolation, a delayed interpolation buffer, and RNG are not required
to produce the defect.

## H1c: correction evaluated, not adopted

The candidate uses **height_change[S+1]** for the initial fractional term,
matching the interval used by the next road point. It retains the existing
forward accumulation and does not advance the track pointer an extra interval.
The look-ahead read must wrap correctly at table index 255.

In exact arithmetic this makes the two sides of each segment boundary agree.
It uses the current camera state and already-loaded track data, so it requires
no presentation history, input delay, extra simulation tick or extrapolation.

In addition to the captured-state evaluation above, an offline boundary sweep
held camera height at 93, player distance at half a segment, and airborne/bobbing
effects at zero. For each captured segment/table configuration, it compared
fraction 65535 with the immediately following segment at fraction zero:

| Track data from | Segment/table configurations | Largest native jump | Largest candidate jump |
| --- | ---: | ---: | ---: |
| enhanced long run | 633 | 17 pixels | 2 pixels |
| option-off long run | 650 | 17 pixels | 2 pixels |
| v2.0 long run | 650 | 17 pixels | 2 pixels |

These counts can include multiple table versions for a segment. This is an
isolated numerical boundary test, not an observed maximum over every game track
or an emulator test with injected positions. Segment 396 improves from Y
122 → 138 to 138 → 138 in all three data sets. The remaining one/two-pixel
steps arise from truncating the fractional camera term and separately rounding
actor interpolation. Retaining fractional precision until the final projection
is a possible refinement, not part of a tested implementation here.

**Evaluation:** the lookup correction is a credible way to remove the large
reference jumps. A rendering-only prototype is justified if implementation is
later requested. A global patch to the common generator is not yet justified:

- Collision projection consumes the same height and occlusion tables. The
  reduced simulation generator in `collision_geometry.s` copies the native
  calculation; changing that input can change gameplay.
- On the selected faster paths, `step_geometry_reuse` consumes the prior
  render geometry once before the next movement update. A rendering-only hook
  must also prevent corrected render tables from being reused for simulation,
  by preserving the required native collision inputs or rebuilding them.
- A prototype must keep road, riders, scenery and clipping on the same corrected
  render reference, including copied object-projection paths. Changing only
  the player Y would leave the road jump and break alignment.
- Any adopted enhancement belongs behind CUSTOM2. It needs checks at table
  wraps and section reloads, hills/jumps/crashes, native and Chip-only fallbacks,
  full-race collision/state equivalence, and the established speed/latency and
  frame-cost checks. Their outcome cannot be inferred from this offline model.

No implementation performance or gameplay-equivalence claim is made. H1c ends
at this evaluation; adopting and validating a correction is deferred.

## Evidence and reproduction

The ignored local harness has `height_trace.py`, `run_height.py`,
`height_model.py` and `height_evaluate.py` under `tmp/dev/tools/`. Captures,
native/candidate model outputs and provenance are in `tmp/dev/tmp/h1-on`,
`h1-off`, `h1-original`, and their `-long` variants. The model checks all native
outputs before evaluating the candidate. `h1-evaluation.json` records the
boundary tests; `h1-validation-final.txt` records the successful model checks.
No experimental slave was built or installed.

Slave/emulator SHA-256 identifiers are the same as those recorded in
[the visibility investigation](visibility-investigation.md#reproduction-and-retained-evidence).
