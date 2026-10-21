# Rider visibility investigation (2026-10-21)

**Follow-up, 2026-10-22:** the user subsequently authorized fixing these inherited
bugs in both framerate modes. [Implementation and validation](visual-fixes.md)
supersede the historical no-patch/evaluation-only disposition below.


Both reported forms of flicker reproduce in the untouched v2.0 game as well as
3.0b with Enhanced framerate enabled. The reproduced disappearances originate
in the native visibility decisions, before drawing. No enhancement regression
or required corrective patch was found. Game behavior is unchanged.

## Report and scope

`Screen Recording 2026-10-21 at 23.21.59.mov` shows a distant rider disappearing
at 70.300 s and returning at 70.400 s. A mirror rider disappears from both mirrors
at 74.698 s and returns at 74.748 s, with another disappearance just beforehand.
Consecutive recording frames establish complete disappearance, not just a pose
change. The recording has no memory/input trace: the controlled runs below
reproduce the mechanisms, rather than replaying those exact recorded moments.

This is separate from H1's unresolved vertical track-height discontinuity.

## Native cause

At `$89e2c..$89e3a`, the game computes a segment difference by subtracting the
integer parts of the rider and camera positions:

```
d = (rider_position >> 16) - (camera_position >> 16)
```

This differs from subtracting the full positions first. Even with smoothly and
monotonically changing relative distance, `d` can alternate as the camera and
rider cross separate track-segment boundaries.

- Forward riders: `$89e68..$89e6c` rejects `d > 30`. At a true separation between
  30 and 31 segments, the decision can alternate between visible and hidden.
- Mirrors: `$89e3c..$89e64` hides a rider at `d == -1` when player speed is at
  least that rider's speed. At `d <= -2` it allows mirror projection (down to
  the rear distance cutoff of -16). A rider falling smoothly behind the player
  can therefore repeatedly enter and leave both mirrors between true distances
  of one and two segments behind the camera.

These instructions are present in the original unrelocated main image. The
enhanced patch list retains these decisions; relocation changes their absolute
data operands, not the comparisons. No interpolation, heading extrapolation,
frame-buffer clear or blitter operation is needed to explain the reproduced
loss of draw records.

## Runtime evidence

Deterministic isolated 68040/25 MHz, AGA, 2 MiB Chip / 8 MiB Fast runs used PRELOAD
and the WHDLoad `Cache` option. The passive debugger build reports CPU data-cache
emulation disabled; this is a visibility-logic comparison, not a hardware cache
validation. No debugger memory writes or synthetic actor states were used.

At `$87670`, immediately after the render's actor traversal, the probe captured
camera/actor state, the active rider list and the generated 20-byte draw records.
Forward examples below use rider slots `$a6460` and `$a64e0`. Both records are
omitted/restored together, changing the list from six to eight records:

| Build | Race field | True distance (segments) | Integer difference | Both rider records |
| --- | ---: | ---: | ---: | --- |
| 3.0b enhanced | 655 | 30.25090 | 31 | absent |
| 3.0b enhanced | 657 | 30.33678 | 30 | present |
| v2.0 | 662 | 30.38004 | 31 | absent |
| v2.0 | 664 | 30.46619 | 30 | present |
| v2.0 | 666 | 30.55276 | 31 | absent |
| v2.0 | 670 | 30.72720 | 30 | present |

The mirror examples use slot `$a6260`, rider 10. Player speed exceeds rider speed
throughout each sequence. The generated mirror object is type `$154`, flags
`$6100`; its record is actually absent on the hidden rows:

| Build | Race field | True distance (segments) | Integer difference | Mirror record |
| --- | ---: | ---: | ---: | --- |
| 3.0b enhanced | 1102 | -1.11604 | -1 | absent |
| 3.0b enhanced | 1103 | -1.12526 | -2 | present |
| 3.0b enhanced | 1104 | -1.13353 | -1 | absent |
| v2.0 | 1060 | -1.11334 | -1 | absent |
| v2.0 | 1063 | -1.13980 | -2 | present |
| v2.0 | 1066 | -1.16626 | -1 | absent |
| v2.0 | 1069 | -1.19533 | -2 | present |
| v2.0 | 1072 | -1.22096 | -1 | absent |

## Reproduction and retained evidence

The local ignored harness contains `visibility_trace.py`,
`run_visibility_trace.py` and `analyze_visibility.py` under `tmp/dev/tools/`.
`public_invoke_d.py` gives the enhanced trace the same original-address view as
v2.0, without modifying game memory. Route to the first race, settle to field
100 and hold throttle. The driven variants additionally steer toward lateral
position zero with a 64-unit dead zone, updating at render stops at least 20
fields apart. This produces overtakes for the mirror comparison. Each build
runs the same controller; the resulting trajectories are not asserted identical.

Evidence directories under `tmp/dev/tmp/`:

- `visibility-on`: 2,600 render snapshots, race fields 101–2833.
- `visibility-original`: 1,888 snapshots, fields 100–4001.
- `visibility-on-driven`: 5,000 snapshots, fields 101–5498.
- `visibility-original-driven`: 2,515 snapshots, fields 100–6001.

Each contains `trace.json`, `threshold-transitions.json`, `provenance.json` and
the tested slave. Video crops and timestamps are in `bike-flicker-video/`.
Full SHA-256 identifiers:

```
3.0b:    00fa8ff709e843569eacc03641f9cb282bdf3a0224aea65345fb606e7bc6cbf1
v2.0:    9d2f23027167611100c96e9909123a2d10259595e353a517ef1ff41eae33a563
emulator:e0b2532ace1de7dd4d66d811488ec67ea7080b9991ee57e7190d8e31483f99cc
```

The investigation establishes inherited threshold oscillation in both paths.
It does not quantify a change in perceived severity at higher frame rates or
exclude unrelated visibility defects elsewhere. Fixing these original rules
would be a separate behavior change, outside the requested conditional fix for
an enhancement-caused regression.
