# Player state inventory — C4a/C4b

This is the first static inventory, not the completed equivalence gate.
Offsets in the first column are **hexadecimal byte offsets** from a5 =
D3B88. Code offsets are relative to the original code hunk. Widths and
arithmetic below describe native storage; physical unit conversions and
exhaustive indirect readers/writers remain to be established.
No field-rate integrator may be enabled on the strength of this inventory.

## Native update order

The main loop selects the player record at +0563A, increments its tick
counter, handles cooldowns, then builds instruments at +056D8 and the
camera vector at +057E2. Rendering starts at +05830. Its result participates
in flight-end handling. The subsequent update calls controls (+04E3C),
motion (+0937C), weapons/actors (+0979C), damage (+09C5C) and scripted
object work (+09F74). Every sixteenth tick performs additional housekeeping
and reserve depletion around +0594C/+0597A.

This ordering means moving the render call alone cannot provide fresh
camera or instrument state.

## Motion and control boundary

| Offset / width | Native meaning and units | Observed writes and dependencies | Proposed owner |
|---|---|---|---|
| 00, 02 / words | Player map coordinates, native coordinate units | +096A6/+096DE integrate and clamp to 1800..D800 hex; +096F0/+096FA add wind while airborne. Read by camera, waypoint and range calculations. | Continuous; world consumes committed position |
| 04, 06 / words | Fuel-like reserves; exact gauge scale pending | Depleted at +0594C/+0597A every sixteenth tick; high bytes feed instruments. These are not ordinary motion-rate decay terms. | World |
| 08, 0A / words | Waypoint coordinates | Read by control bearing calculations in +05336 path. Full producer audit pending. | World/navigation |
| 0C / word | Native tick counter | Incremented at +05640; parity affects vertical rounding at +0957C; also drives housekeeping. | World |
| 0E / word | Damage flags | Read by attitude/motion perturbations, written by damage logic. | World |
| 14, 15 / bytes | Signed wind displacement components | Added to player coordinates at +096F0/+096FA while airborne. | World sets; continuous path applies scaled displacement |
| 18 / byte | Flight-end state | Ground logic writes at +095EE; main loop also consumes render results. | World |
| 1A / byte | View heading offset | Command writes at +05018/+05026/+05036; camera combines with heading. | Presentation/control |
| 1B / byte | Engine/RPM-like value | Approaches target or coasts at +0974A/+09794; exact gauge scale pending. | Continuous response to world engine state |
| 1C / word | Player altitude, native height units | +09598 integrates signed vertical rate with tick-parity rounding. Camera adds 24 native units. Ground handling follows immediately. | Continuous height; world contact consequences |
| 2A / word | Signed forward speed | +0966E applies rounded approach to target at 30; reset on ground at +0962A. Drives horizontal displacement. | Continuous; world can reset |
| 30 / word | Target forward speed | +09502/+09528 derive from native flight terms. | Continuous derived value |
| 35 / byte | Heading, wrapping native angle | +09414/+09456 integrate yaw/bank; +0948E can add random damage perturbation. Camera negates heading plus view offset and shifts by 8. | Continuous angle; world random impulse |
| 36 / byte | Pitch, signed native attitude | +053C0/+053EA control path; ground reset +09632; weapon recoil +099A4. Camera uses signed half-pitch shifted by 8. | Continuous control; world recoil/reset |
| 37 / byte | Roll, signed native attitude | +05398/+053AE control path, clamp -20..20; ground reset +0962E. Camera negates and shifts by 8. | Continuous control; world reset |
| 38 / byte | Effective power | Derived at +093F4. | Continuous derived value |
| 39 / byte | Collective setting, range 0..42 | Command path +05040..+050A2 changes it. | Field-stamped control target; world reads |
| 3A / byte | Lift-related term | Derived at +094DC. | Continuous derived value |
| 3D / byte | Track heading | +09432/+09470 update it. | Continuous derived value |
| 3E / byte | Signed vertical rate | +09572 adds rounded quarter-error; ground reset +09626. | Continuous; world reset |
| 3F / byte | Yaw control, clamp -4..4 | Command changes +052A6/+052B0, clamp +052E4; clear +05154/+052F6 and +0945A. | Field-stamped control, with native consumption semantics to resolve |
| 40 / byte | Target engine/RPM-like value | +09728 derives from engine flags and collective. | Continuous derived value |
| 50 / byte | Coarse speed | +09674 derives speed shifted right by two. | Continuous derived value |
| 52 / byte | Crash/landing state | +09604/+09622 ground logic. | World |

## Record contents that must not become player motion

The same record stores temporary data for other objects. +07B7E loads and
+07BD0 stores object state through fields 1E/20/22 and 4B/4C/4D.
The scripted-object path +09F74 uses deltas at 26/28, range at 2E and
script state at 53/54. These remain world-owned. A blanket preview or
integration of every byte in the player record would corrupt this boundary.

Weapon selection, ammunition, pending launches, cooldowns, engine flags,
mission configuration and damage state also remain world-owned. Their
complete field-by-field writer/reader catalogue is still pending; the
motion table is not a claim that these fields are unused.

## Gates before C4c

* Complete indirect writer/reader coverage, including initialization,
  mission transitions, damage, weapons and scripted paths.
* Confirm reserve and RPM semantics, physical coordinate/height scales,
  and all byte signedness from native arithmetic and displays.
* Separate RNG calls at +05380/+053DC and +0948E from continuous preview.
  A field step must not advance world RNG extra times.
* Preserve weapon recoil and ground resets as world impulses; do not
  suppress these when skipping already-integrated native motion.
* Resolve the tick-parity vertical rounding and consumed yaw-control
  semantics in the h=1 equivalence fixture.
* Inventory every instrument output and camera destination, then establish
  the complete save/restore set before calling native code in preview.

The first inventory report therefore identifies the continuous/world
boundary but does not close C4a or C4b.
