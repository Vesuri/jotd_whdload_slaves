# Player state inventory — C4a/C4b

This is a static inventory with native-code execution checks, not the completed equivalence gate.
Offsets in the first column are **hexadecimal byte offsets** from a5 =
D3B88. Code offsets are relative to the original code hunk. Widths and
arithmetic below describe native storage; physical unit conversions and
exhaustive indirect readers/writers remain to be established.
No field-rate integrator may be enabled on the strength of this inventory.

## Initialization boundary

+020F6..+02106 passes length 86, value zero and the player-record address
to the native fill routine. This resets every byte, including fields not
individually assigned later. Fractional player state must reset at this
boundary too.

The subsequent mission loads write record offsets 16/17 (mission parameters),
04/06 (reserves), 10/11 (configuration/difficulty), 12 (load parameter),
14/15 (wind), 00/02 (position), 0E (damage), 13 (damage count), 0C (tick),
19/18 (mission state). The sources are longs in the mission block; native
stores truncate them to the destination byte/word. +021C8/+021E0 set
waypoint words 08/0A from selected object coordinate high bytes shifted by
eight. These are world initialization writes, not integration increments.

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
| 36 / byte | Pitch, signed native attitude | +053C0/+053EA control path; HUD clamp/writeback +05776; ground reset +09632; weapon recoil +099A4 and +09B6E. Camera negates in byte width, then arithmetic-shifts right one and shifts into the high byte. | Continuous control/clamp; world recoil/reset |
| 37 / byte | Roll, signed native attitude | +05398/+053AE control path, clamp -20..20; ground reset +0962E. Camera negates and shifts by 8. | Continuous control; world reset |
| 38 / byte | Effective power | Derived at +093F4. | Continuous derived value |
| 39 / byte | Collective setting, range 0..42 | Command path +05040..+050A2 changes it; +0513A clears it. | Field-stamped control target; world reads |
| 3A / byte | Lift-related term | Derived at +094DC. | Continuous derived value |
| 3D / byte | Track heading | +09432/+09470 update it. | Continuous derived value |
| 3E / byte | Signed vertical rate | +09572 adds rounded quarter-error; ground reset +09626. | Continuous; world reset |
| 3F / byte | Yaw control, clamp -4..4 | Command changes +052A6/+052B0, clamp +052E4; clear +05154/+052F6 and +0945A. The shared command tail clears it for every nonzero coarse speed, including for unknown commands. | Field-stamped control; world decoder must not replay its common tail |
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

## Camera and instrument outputs

The +057E2..+0582A builder writes six consecutive words at **hunk 4 +0000**:
x, y, altitude plus 24, negated heading-plus-view-offset, negated half-pitch,
and negated roll. The last three are byte arithmetic shifted left eight
bits into native angle words. Preserve byte wrapping and the order of pitch
negation and arithmetic shift; `-(pitch >> 1)` is not equivalent for odd
values. +04288 consumes this camera/state vector in the original renderer.

The +056D8..+057DC instrument builder writes these hunk 6 outputs:

| Offset / width | Input / transformation | Write site |
|---|---|---|
| 157D, 157E / bytes | High bytes of reserve words 04/06, logical shift right 2, gauge conversion then OR 80 hex | +056E8/+056FE |
| 157F, 1580 / bytes | Collective shifted right 1 and gauge-converted; independently zeroed when engine flag bits 2/3 are clear | +05722/+05736 |
| 1582 / byte | RPM-like byte 1B shifted right 3, gauge conversion | +05748 |
| 1586 / byte | Heading byte 35 | +0574E |
| 1588 / byte | Pitch clamped to -12..20 | +0577A |
| 1589 / byte | Negated roll byte 37 | +05786 |
| 158A / byte | Low speed byte 2B minus coarse speed byte 50 | +057B6 |
| 1584 / word | Altitude plus logical altitude/4, word arithmetic | +057C6 |
| 158C / byte | Vertical rate shifted into high byte, arithmetic-halved, transformed by +07A1C, then high byte selected | +057DC |

The gauge conversion at +05A10 forms `x + (x >> 1)` with byte arithmetic,
then caps it at 31. Damage bit 4 in record byte 0F overwrites seven gauge
bytes starting at 157D with 80 hex at +057A2. This includes retained
initialization values at 1581/1583; it is not simply a transformation of
the five gauges computed in this block.

**The instrument builder is not read-only.** +05776 stores the clamped
pitch back into record byte 36. That currently happens before rendering,
after the preceding tick's controls/motion/recoil. Rebuilding instruments
more often must not introduce extra authoritative clamps. The field-rate
player path needs an explicit corresponding clamp point, and the h=1
fixture must preserve its order relative to control and weapon impulses.
The two recoil writes subtract one (+099A4) and four (+09B6E) respectively;
the latter depends on weapon-selection bit 0.

The standalone `timing-presentation.i` builder now reproduces these outputs
without player writes; a separate `player_pitch_clamp` retains the native
authoritative operation. All 65,536 pitch/vertical-rate byte pairs compare
against the original builder when the clamp is applied first. This proves
the extraction, not its eventual scheduling relative to controls/recoil.
The lower clamp check uses BMI after byte subtraction, not signed BLT;
out-of-range positive pitch bytes 116..127 therefore also become -12.
The helper preserves that behaviour.

The enclosing render routine also reuses a5 for a different structure.
In particular +05C24 and +060D2/+06156/+06200/+06236 are not player
position/speed writes despite their matching numeric displacements.

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

The command ownership table and 86,688-case native decoder check are in
`TIMING_DESIGN.md`. In particular, command 03 changes world-owned flags
and can reset player-owned collective. The standalone `timing-control-mode.i`
helpers now preserve the reset's field order while deferring the actual flag
and indicator update. Queue-dispatcher installation and lifecycle reconciliation
remain required. Command effects are not cleanly separable by key alone.

## Executed native motion and control audit

`tmp/dev/tools/audit_player_motion_c.py` executes the original +0937C
airborne routine against a retained full-memory snapshot. In 384 cases
spanning pitch, roll, yaw, speed, vertical rate, damage, engine flags, wind,
power and map boundaries, its player writes cover exactly these 14 fields:
00/02/1C/2A/30 as words, and 1B/35/38/3A/3D/3E/3F/40/50 as bytes
(19 bytes total). The observed writer PCs match the table above.
This is an airborne-path result: ground contacts and other callers remain
outside this coverage.

Outside the player record and stack, the only observed writes are to the
gameplay RNG seed at hunk 4 +03CC, including its low word at +03CE.
The RNG writes occur at +07A96 and +07ABE. A preview cannot advance this
seed, nor can it turn a native world-rate damage impulse into field-rate
noise. Merely restoring the seed does not resolve impulse timing/ownership.
The original input/output records and access lists are retained in
`tmp/dev/tmp/c/player-motion-fixtures.json` and `player-motion-accesses.json`.

The native +07A44 trigonometric helper indexes a 256-entry signed table at
hunk 4 +01C8. Samples at angles 0/64/128/192 are 0/32767/0/-32767.
It multiplies by the signed amplitude, doubles the product and takes the
high word: the native fixed-point sine operation, with its signed rounding.
This establishes useful integration units without guessing physical labels:

* Heading and track heading use 256 native angular units per turn.
* Speed word 2A is in quarter map-coordinate units per native tick.
  Its arithmetic shift by two is narrowed to signed byte 50 before the
  sine/cosine displacement calculation. Preserve that narrowing in h=1.
* Signed wind bytes are direct map-coordinate increments per native tick.
* Vertical-rate byte 3E is in quarter native height units per tick. Height
  integration first adds `(tick & 1) + 1` in **byte** width, then arithmetic
  shifts right two and sign-extends. Byte wrapping and tick parity matter.
* Vertical-rate approach uses one quarter of the error, forward-speed
  approach uses one sixteenth plus a signed one-unit slew term, and the
  powered RPM response uses one eighth. Their rounding offsets are 2, 8
  and 4 respectively. They cannot all be replaced by one generic decay.
* The unpowered/coasting RPM path is additive and clamped, rather than
  the powered path's one-eighth approach. Its increment depends on
  collective, coarse speed and whether the player is on the ground.

`tmp/dev/tools/audit_player_controls_c.py` separately executes +05376,
the attitude tail after navigation/waypoint work. Across 972 cases covering
all current x/y and previous-y directions, representative roll/height states
and damage, its only writes are pitch byte 36, roll byte 37 and the same RNG
seed. The navigation prefix +05336..+05374 is not covered by this result.

Without random impulses, roll adds four times the current x direction and
clamps to -20..20. Pitch changes only when current y is nonzero, subtracting
`current_y + previous_y`. Previous y is the byte at code hunk +05524, copied
from the preceding native control sample by +04E42. Reversal therefore
cancels the first native increment, while sustained deflection doubles it.
The field-rate equivalent needs an explicit previous-control state and
transition tests; treating direction alone as a rate would miss this. The
copy occurs in the world decoder called at +05884, not in the VBL sampler.
The continuous-player delay wrapper now retains 17/20 fields of y history
to preserve that time horizon. The split ground transaction also retains
and commits this history; scheduler adoption remains pending.

The pitch perturbation at +053DC is not conditional on the roll-damage bit:
it can run when the high altitude byte is zero, speed is at least eight,
and the low altitude byte is below the low speed byte. This is another
world-owned random impulse, with its predicate evaluated at the intended
world boundary. Evidence is retained in `player-control-accesses.json`.

The standalone attitude component now accepts these two world impulses
explicitly: roll -4/0/+4 before the native clamp, pitch -1/0/+1 after stick
control. It never generates RNG values. Its h=1 path matches the original
attitude routine in 68,040 cases using captured native random outcomes.
This closes the application-order question for that component; world-rate
eligibility, RNG call order and once-only delivery remain integration work.

## Ground boundary execution check

`tmp/dev/tools/audit_player_ground_c.py` executes +095A0..+09636 in 864
cases after altitude has reached zero, varying previous airborne status,
speed, vertical rate, roll, configuration and damage. The external
notification routine +0A150 is replaced with a return in this fixture;
its own side effects are outside this coverage. The native branches and
player stores are executed unchanged. Results are retained in
`tmp/dev/tmp/c/player-ground-audit.json`.

All cases clear speed word 2A and pitch/roll/vertical-rate bytes 36/37/3E.
This reset happens even when the player was already grounded. The native
code preserves the pre-integration airborne test in d2 at +09576..+0957A;
that flag controls whether landing/crash classification runs before the
reset. The fixture reaches crash states 0/2/3/4 and 270 flight-end cases.
These counts describe fixture coverage, not gameplay probabilities.

The special flight-end branch also writes a notification timer at hunk 6
+42F6 (+095F4), in addition to calling +0A150 and setting player byte 18.
Thus the airborne routine's player-bytes-plus-RNG save set is insufficient
for previewing ground contact. The field step must retain pre-step contact
information for world evaluation and must not repeatedly execute these
notifications or authoritative resets on each rendered field.

The standalone `timing-motion-preview.i` now copies the native arithmetic
and bypasses the random-heading and contact blocks in that copy. It runs
on a separate 86-byte record. Memory-write checks across 4,096 cases find
no writes outside that result and the stack. This establishes a usable
continuous-arithmetic preview boundary, without claiming that omitted
world effects or fractional integration have passed C4e. Detailed test
scope and installation/cache obligations are in `TIMING_DESIGN.md`.

## Projectile eligibility changed by VBL control state

The native weapon constructor clears an allocated guided slot's eligibility
bit at +0BBC8..+0BBD2 (except weapon type 2). Actor updates require both its
allocation bit (hunk 0 +0BA08) and eligibility bit (+0BA0C). The guided slot is
recorded in +0BA0E. VBL +04C12 calls +0A1C8; control state 5 reaches
+0A234..+0A242 and sets that eligibility bit. These are external world-visible
writes, in addition to the player-record inventory. Field-history catch-up
must preserve their ordering and slot identity before consuming a deadline.
A standalone field-owned guidance step now preserves the native transitions
with a private next-field acknowledgement in place of the screen-swap flag.
It is bound to delivered scheduler fields in standalone tests, but is not
yet installed in gameplay. See TIMING_DESIGN.md for
the transition and hybrid-handshake tests and remaining presentation work.
