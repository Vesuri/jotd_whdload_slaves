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
and commits this history. The scheduler bridge now supplies each delivered
field stamp to that transaction; production installation remains pending.

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


### World-written VBL countdown bytes

Three hunk-6 bytes are shared between world setters and native VBL work:

| Offset | Native VBL decrement | World writers / use |
| --- | --- | --- |
| 4296 | +04BA8, only if nonzero | Hit routine +07E5A/+07E92 ORs 24/8; hit-flash/audio response. |
| 42F6 | +04BBA, only if nonzero | Ground +095F4 sets 180; hit +07E54/+07E8C ORs 24/8; VBL response amplitude. |
| 42F7 | +04C32, only if nonzero | Damage +09E22/+09E48 sets 64/128; render +05C8A tests effect eligibility. |

The first two update before guidance +04C12; the third follows it. Native
+04B48 skips these updates when the signed quit byte (hunk 4 +01C6) is
negative. Guidance itself requires quit exactly zero. The standalone
`field_vbl_state` preserves both gates and this order; its scheduler wrapper
runs once per delivered field. Installation must remove the original VBL
writes and coordinate cosmetic readers, which can need pre-decrement values.
No native VBL hook is changed yet. See TIMING_DESIGN.md for comparison scope.

### Render-produced flight-end flag: plane reduction checkpoint

The shared byte at hunk 6 +3958 is cleared by render +05C28 and overwritten
by +0691C. The main loop reads it at +0583C after rendering; a nonzero value
sets player +18 to 1 and branches to cleanup. This remains an unresolved
render-to-gameplay dependency and is not yet moved into the world owner.

The producer starts at +06818. Its +068F8..+06922 plane loop consumes four
signed words per plane (three normal components and a distance), computes
three MULS.W products with wrapping long additions, then marks visibility
using CMP.L/SMI. This tests the subtraction's N flag, not signed less-than
(N xor V). The final SEQ sets the shared flag when no plane was marked.
A zero plane count returns earlier and leaves the shared flag unchanged.
Each nonempty shape overwrites the byte; this is not an accumulated OR.

`timing-face-planes.i` extracts only this read-only reduction. It returns
0 for any facing plane, 1 for none, 2 for zero planes (no decision), and -1
for invalid scalar arguments. It preserves other registers and writes only
the stack. Coordinate preparation, shape selection, and shape ordering are
explicitly outside its contract. The caller at +063F2 is inside shape
processing +063DC; the outer +0625C..+06370 loop advances the object index
and shape pointer. Those inputs and transforms must be traced before this
can become an authoritative world-tick flight-end test. It is not installed.

The ignored `tmp/dev/tools/test_face_planes_c.py` fixture compares the
assembled helper with actual native +068F8 instructions for 1,100 seeded
random/extreme cases, including counts 1 and 255. It independently checks
all native visibility bytes, observes 25 comparisons where overflow makes
SMI differ from signed less-than, checks four zero-plane prior flag values
through native +06818, and rejects five malformed scalar arguments. All
cases pass, including register preservation and write-address checks.
This proves the reduction only, not collision behavior or timing acceptance.

#### Shape selection and projection separation

The +060A8 scene pass traverses nine cells in each of two table-selected
orders (+060B6 and +06142). It takes shape counts and list offsets from
hunk 6 +1D0C and +1CA6 respectively, with shape storage based at hunk 6
+15DC. Each six-byte shape-list entry supplies an offset index, a size/type
index, and two model offsets. +0625C first consumes a visibility-mask bit;
+0628A..+06312 then reject using transformed depth and lateral extent.
+06316 compares distance with the type threshold, and +06322 advances the
entry pointer by two when selecting the alternate model. Model -1 is the
point-drawing path; -2 selects the inline model at hunk 0 +5A24. Other
models are relative to the shape-storage base. This is a view-dependent
candidate/LOD selection, not simply enumeration of all nearby world shapes.

After both cell passes, +061AE optionally processes the special object
selected by context +3E, subject to the native Manhattan-distance check
against 96. Its shape index is -1, selecting the rotated/height-adjusted
plane-coordinate path. The separate +06224 pass supplies twelve entries
with its own visibility mask. These paths must retain their ordering and
native model choices in an h=1 comparison; a world collision owner cannot
silently substitute an OR over the rendered shapes or consume predicted poses.

A model begins with a byte containing vertex count minus one. Each vertex
uses one byte unless it is FF, in which case it consumes three. Native
+06642 changes the model pointer by two for the latter case while restoring
the logical vertex index before returning. Thus +063EE/+063F0 can locate
the plane-count byte without projecting any vertices. Removing projection
must retain that variable-length traversal.

`tmp/dev/tools/audit_scene_planes_c.py` runs native +060A8 from the captured
flight snapshot, returning before polygon rasterization, omitting draw
submission, and bypassing the point-only drawing branch. It first retains
native vertex projection, then repeats on a fresh CPU with only the vertex
record traversal. Both runs select the same 17 shapes, three with nonzero
plane counts (5, 4, 5), in the same order. Plane pointers, every facing byte,
and the final zero flag agree. This demonstrates projection separation for
that snapshot only. It does not cover the special object, the separate
twelve-entry pass, all LOD/culling transitions, or rebuild the cached scene
transforms from committed player/world state. Those remain necessary before
installation as a world owner; no timing or rendering hook is changed here.

#### Committed scene endpoint and transform rebuild

The native +04288 routine is itself an interpolation loop. It builds a
27-word vector, subtracts the prior endpoint at hunk 5 +0A, then writes
intermediate vectors to hunk 6 +3904 (render context +0E). +043F0..+0440C
finally adds each difference back to the prior endpoint and publishes the
exact current vector. A world collision check must not read an arbitrary
intermediate buffer left by this loop.

`timing-scene-state.i` now constructs that 54-byte endpoint directly from a
committed 12-byte camera vector, the 36-byte six-object coordinate vector
(native hunk 0 +C6A0), and the special object's six split coordinate bytes
in hunk 6. It writes a caller-owned destination only and does not use the
previous-frame buffers or native interpolation counters. Input stability
and non-overlapping destination are caller contracts. This standalone helper
is not installed, and world callers must never supply predicted poses.

`test_scene_state_c.py` compares 512 seeded endpoint cases with the actual
+04288..+0444A instructions, stubbing only the renderer at +05C04. It varies
prior endpoints, the six-slot mask, and interpolation periods 1/3/20/50.
All 54 bytes match after 8,960 total intermediate images; register, write
range and destination-canary checks pass. These cases establish endpoint
construction, not native interpolation's suitability for the new design.

The scene audit also now supports `REBUILD_SCENE=1`: native +057E2 builds
camera words from the captured player, the new helper supplies the committed
scene endpoint, and +05C2E..+05C5C rebuilds the native coordinate preparation.
That preparation computes angle factors, calls +05F8E for cell selection and
local-coordinate rebasing, +05CBE for basis preparation, and +05EA4 for
transformed coordinate tables. Repeating native +060A8 with and without
vertex projection again yields identical selection, visibility bytes and
final flag (17 shapes, three nonempty). This uses current captured inputs
instead of the cached scene transforms, but still writes native render
scratch. Private scratch relocation, special-object and projectile-pass
coverage, view/cell boundaries and positive collision cases remain open.

#### Scene boundary and scratch-write comparison

`test_scene_selection_c.py` extends the rebuilt-scene comparison to 96
synthetic scenes: four XY positions straddling native cell/rebasing
boundaries, three heights, and eight headings. Each fresh input runs both
+060A8 and +06224, comparing native vertex projection with traversal-only
vertex processing. Polygon and point drawing remain explicitly omitted.
Six valid projectile coordinate slots are enabled (mask 003F); the special
object is colocated with the camera for the zero-height cases and nearby
for the others, with a varying relative heading.

The corrected fixture passes with 1,210 shape visits, 40 negative-index
special-object shapes, 271 nonempty plane sets, and 32 nonzero final flags.
Model order, plane pointers, every facing byte and the final flag agree.
This includes geometry-positive synthetic cases, but is not a gameplay
collision/trajectory acceptance test. An earlier fixture enabled mask 0FFF,
which selected non-model bytes beyond the six supplied slots; those results
were discarded. The corrected fixture additionally rejects unexpected
plane counts above 20 in these particular captured models.

The same fixture records every non-stack write during coordinate preparation
and both scene passes for the traversal-only path. Writes fall in hunk 0
selection variables, transformed-coordinate/basis arrays and face-visibility
scratch; hunk 6 coordinate template entries and the scene context; and the
shared +3958 result byte. Exact observed address ranges are saved in ignored
`tmp/dev/tmp/c/scene-selection-comparison.json`. No unaccounted world object
writes were observed in these cases. The observed ranges are evidence for
relocation, not a complete static write-set proof: indexed accesses must be
bounded for all supported models before defining private scratch storage.

#### Private scene geometry implementation

`timing-scene-private.i` now provides a standalone prepared geometry path.
It copies native +05A24..+077B8, relocates 151 verified HUNK relocation entries
to private code/scratch, coordinate templates and scene context, and replaces
vertex projection with record traversal. It returns before polygon drawing,
bypasses point drawing and draw submission, and returns before the UI work
after coordinate preparation. The workspace is 7,864 bytes including native
hunk bindings. Preparation validates all relocated addresses and patch-site
signatures before writing; the caller must flush instruction caches once
before execution. Source hunks and model data must be the validated 0658
layout, with non-overlapping buffers.

`scene_private_step` accepts committed camera/object vectors, constructs a
fresh scene endpoint, rebuilds coordinate selection/transforms, runs both
native passes, and returns the final native flag as 0/1. It preserves native
view/LOD/order semantics. Native model/map/actor inputs remain shared read-only
inputs and must be stable during the call. Its output does not itself mutate
the player or run cleanup. Thus this is a geometry primitive, not yet the
scheduled world collision owner or a guarantee against concurrent mutation.

`test_scene_private_assembled_c.py` compares the assembled prepare/step with
the native projected path for the same 96 boundary/special-object scenes:
1,210 shape visits, 40 special shapes, 271 nonempty plane sets, and 32 positive
final flags. It repeats each call using the same workspace. Results and all
visibility bytes agree, registers are preserved, observed writes stay within
private storage/stack, and the native code/data images remain byte-identical.
Each of 151 relocated pointers plus seven patch signatures is independently
corrupted: all 158 preparations reject without changing the destination.
These pass. The prototype relocation script uses the executable's HUNK
records, not scanning for address-looking values. Production integration,
world-phase ownership, lifecycle handling and collision trajectory acceptance
remain pending; the primitive is not installed in the slave.

#### Committed-player and scheduled scene wrappers

The camera-only part of `presentation_build` is now shared as
`native_camera_build`; native byte wrapping and NEG-before-ASR half-pitch
remain unchanged. The existing exhaustive presentation comparison passes
all 65,536 pitch/vertical byte pairs and 256 repeated-render checks after
this refactor.

`timing-world-scene.i` binds the authoritative player to the prepared scene's
native hunk 6, builds the camera on the stack, and checks committed world
coordinates. A positive result sets player +18 to 1, matching native +05846;
a clear result preserves the previous byte. Cleanup and further world work
remain the caller's responsibility. `test_world_scene_c.py` compares all 96
scene cases and checks that the end byte is the only world-state mutation.

`timing-scheduled-world-scene.i` requires scheduler phase 2 with a due world
tick, after player publication. Its 26-byte context binds scheduler, player,
private scene and committed coordinate vector, and records field/valid,
per-call committed status and geometry result. It rejects the same field
twice, checks upstream health before and after application, and retains the
applied field/result when a post-check faults. It does not acknowledge the
world tick or perform cleanup. Positive results must divert to cleanup before
weapons/scripts/tail; this owner connection remains to be installed.

`test_scheduled_world_scene_c.py` passes the 96 native geometry comparisons
and duplicate-deadline checks, three wrong-phase/due checks, and a fault
injected on the second scheduler health check after a positive result. The
player end byte and applied metadata survive the fault; retry after clearing
the upstream fault is rejected. These standalone checks do not yet constitute
full scheduled-player/world composition or moving collision acceptance.

#### Geometry-gated world body

`timing-world-scene-body.i` composes scheduled geometry with the post-motion
world body. It validates body/player bindings before application, consumes
the body phase before the check, and routes a positive result directly to
native cleanup. Weapons, damage, scripts and the periodic tail are skipped
on that path. A clear result runs the existing body sequence; modal handling
still belongs to its lifecycle owner. Geometry/check faults leave the body
in its in-progress/error phase, retaining applied geometry metadata for
recovery. The coordinator does not acknowledge the scheduler's world tick.

The combined fixture now includes the geometry modules, checks geometry on
every due deadline after committed player motion, and rejects repeated
geometry evaluation. Assembly exposed constant-name collisions with the
script and guidance modules; the geometry constants now use `SCENE_` and
`SGE_` prefixes so all modules coexist.

A positive colocated-special-object fixture compares the coordinator against
native flight-end cleanup over the full native state window. State matches
byte for byte; entry tracing confirms cleanup executes once with no weapons,
damage or script entry. Body phase becomes ended, geometry retains its
applied result, and the scheduler remains pending explicit world completion.
A repeated coordinator call is rejected without state changes or cleanup.
This establishes cleanup routing, not lifecycle recovery or moving-contact
acceptance. The native slave timing remains unchanged.

The integrated `test_scheduled_world_c.py` run passes 1,440 delivered fields
at 50/60 Hz with batch sizes 1 and 25 (23,900 helper calls). For each rate,
all committed poses and normalized native world states agree across batches.
PAL observes 21 world deadlines, six launches and 90 actor visits per run;
NTSC observes 18 deadlines, six launches and 72 actor visits. This fixture
remains airborne and retains its explicit UI/visibility/target stubs; it does
not establish native-versus-field-rate moving collision equivalence.

#### Moving-geometry acceptance failure

`measure_moving_scene_c.py` now evaluates geometry along 44 ten-second
trajectories: nine held stick directions plus reversal and pulse tapes,
two flight configurations, and PAL/NTSC. Motion uses the assembled delayed
control integrator. Each trajectory gets one stationary special object at
its native five-second endpoint, with altitude equal to native camera
altitude (player height +24). Both paths use that identical object pose and
world scene. The measurement tests geometry at every world deadline without
applying collision feedback; later hit observations are therefore
counterfactual probes, not continued gameplay after a crash.

**C4e/C5b do not pass.** Of 1,320 boundary comparisons, 82 hit/no-hit results
differ: 54 native hits are absent on the field path and 28 converse results
occur. All 44 trajectories miss the deliberately colocated native hit at
tick 15. This includes neutral input; the failure is not confined to control
reversals or PAL deadline rounding. `check_moving_scene_native_c.py` separately
replays original +05756 clamp, +05376 controls, and native motion with only
world RNG/contact bypassed. All 1,320 reference records match, normalizing
only the saved logical clock word, which the reference interval wrapper
restores. The reference trajectory is not an unverified rewritten model.

Minimal neutral-input example (configuration 0, NTSC, no impulses/commands):
initial player XY 7000/8000 hex, height 1024, RPM 128, collective 30,
engine flags 28, other record bytes zero. At world tick 15 / field 300:

| Quantity | Native | Field-rate |
|---|---:|---:|
| X / Y | 28672 / 32768 | 28672 / 32768 |
| Committed height | 1061 | 1058 |
| Height including shadow fraction | 1061 | 1058.8 |
| Committed vertical speed | 11 | 11 |
| Committed RPM | 153 | 152 |
| Geometry flag at object XYZ 28672/32768/1085 | 1 | 0 |

The first deadline already has height 1025 native versus 1024 committed
field-rate. The gap grows while vertical response and RPM converge. Native
height uses the updated vertical byte for a whole tick, whereas the current
field path scales the quantized native height increment while the response
changes across the interval. Coupled response/position ordering and rounding
must be resolved; changing only the renderer or expanding collision bounds
would not establish the required handling equivalence. No tolerance or
acceptance decision has been invented to pass this result.

Raw poses, shadow-aware samples, stationary object positions and every hit
pair are retained in ignored `tmp/dev/tmp/c/moving-scene-comparison.json`.
The measurement executes 28,295 helper calls. These results supersede any
interpretation of the earlier batch-invariance or isolated geometry tests as
moving-contact acceptance. Native production timing remains unchanged.

#### Selected endpoint-preserving replacement

The user selected preserving native motion at world-tick boundaries while
keeping field-rate input and motion responsive. The preceding failed
measurement remains evidence about the old coupled substep integrator.
It is not an accepted rounding tolerance.

`prototype_endpoint_motion_c.py` now evaluates an alternative: retain the
player record at interval start, preview a complete native tick from that
anchor using each field's current decoded controls and delayed previous-Y,
and add one interval share of the candidate-minus-anchor motion. The ten
distributed quantities are X, Y, height, forward speed, RPM, heading, track,
pitch, roll and vertical speed. Heading/track use circular byte deltas.
Other candidate bytes are provisional derived outputs in this experiment;
their publication and world-field ownership still require an assembly
coordinator. Native previews use the already checked assembled h=1 path.

The share is 1/N, where N is the delivered interval length: PAL 17/17/16,
NTSC 20. This deliberately replaces fixed 3/rate response substeps so each
delivered deadline reaches the native endpoint. Python exact fractions
retain residue between intervals. All 44 ten-second paths now match all
86 reference bytes at all 1,320 world boundaries. Running the same private
scene geometry against the retained stationary objects also matches all
1,320 native hit decisions. As before, these are counterfactual collision
probes without collision feedback, world commands or ground transitions.
The prototype has not established coordinate-wrap behavior or live latency.

A separate NTSC pulse on fields 5–9 changes fractional roll on field 5,
reaching one roll unit before the deadline and retaining it after release.
This demonstrates that the experimental scheme does not merely postpone
controls until the world tick. It intentionally differs from a native tick
that would miss an entire inter-tick pulse. The first fractional change is
not yet evidence of an installed camera or visible screen response.

`timing-endpoint-fraction.i` is the first standalone assembly primitive for
this replacement. It distributes a candidate delta over 16, 17 or 20 fields
with denominator 1360, their least common multiple, retaining exact fractions
across PAL interval-length changes. A one-field mode preserves the native
whole-step delta. Integer publication uses floor with nonnegative residue.
The caller owns shortest circular deltas, native-width wrapping, interval
anchors and field ownership. No game code calls the primitive yet.
`test_endpoint_fraction_c.py` passes 4,395 boundary/random/invalid-input and
cross-interval cases, including signed delta limits, register preservation
and rejection without writes. C4e/C5b remain open until the replacement is
composed with the scheduled player/world path and its remaining gates pass.

`timing-endpoint-motion.i` now applies that exact arithmetic to the ten
continuous fields. Its 40-byte residue vector follows the order listed
above. X/Y use shortest signed word deltas, heading/track shortest signed
byte deltas; publication wraps at the native width. Height/RPM differences
are unsigned, and speed/pitch/roll/vertical differences are signed. The
caller supplies separate anchor, candidate and current-player records.
Only the ten motion fields are changed: derived outputs, yaw consumption,
clock and all world-owned bytes remain caller responsibilities. The helper
validates the interval length and every residue before its first write.

`test_endpoint_motion_c.py` passes 1,526 assembled cases against an independent
integer model, covering random records and residues, extreme signed and
unsigned deltas, wrap crossings, exact complete-interval endpoints, varying
per-field candidates across PAL/NTSC intervals, and invalid final residues.
It checks preservation of anchor/candidate records, registers, all other
player bytes, and rejection without state changes. This tests distribution,
not native candidate construction or publication ownership.

`test_endpoint_player_c.py` substitutes the assembled distributor into the
native-preview trajectory experiment. All 24,200 fields match the exact
fraction model, and all 1,320 complete player records and collision decisions
match the retained native reference across the 44 paths. The additional
20-field pulse also matches the fractional roll response, including its
first-field change. Results are in ignored
`tmp/dev/tmp/c/endpoint-motion-assembled.json`. The harness still coordinates
anchors/history and provisionally copies non-motion bytes from each preview;
this is not yet a scheduled assembly player owner or a ground/command test.

#### Transactional endpoint player owner

`timing-endpoint-player.i` now owns an airborne interval's anchor, ten exact
residues, delayed-control history, span, consumed-field count and logical
tick in 164 bytes. Initialization validates the display rate/previous input.
Beginning an interval requires the previous interval to be complete, retains
fractions/history, and captures the post-world player record. The scheduler
must select PAL's 17/17/16 spans; NTSC accepts 20, whole-tick fixtures 1.
Mission/pause rebasing still belongs to the lifecycle owner.

Each field uses private working state: it advances delayed input, previews
native h=1 motion, distributes its contribution, then publishes the result
and history together. Invalid or repeated/skipped fields, invalid controls,
invalid fractions and an exhausted interval cannot publish or consume history.
This is a foreground transaction, not interrupt-atomic memory publication.

The preview overlays anchored continuous quantities onto the current record,
allowing current collective, engine flags and other command/world inputs to
affect this field. One derived value must also be anchored: native +0939C
reads previous coarse speed (`50`) before +09674 replaces it. An initial
configuration-2 reversal test exposed power/target drift at field 36 when
the previous field's candidate coarse speed fed the next preview. Retaining
the interval's coarse speed removes that unintended feedback.

Publication changes the ten continuous fields and derived target speed,
effective power, lift, RPM target and coarse speed. It preserves all other
current bytes, including clock and command inputs. In particular, preview
yaw consumption is published only on the final field at the world deadline,
using the native preview's result as described below. Nonzero impulse words in the packet are rejected;
world kicks must be applied once before anchoring rather than diluted into
one field's contribution. Ground contact and world kick scheduling remain
unfinished. The standalone
owner must not be installed as a complete replacement for those paths.

`test_endpoint_owner_c.py` compares the assembly owner with the earlier
independently orchestrated native-preview/distribution experiment for neutral,
reversal and pulse tapes, both flight configurations, PAL and NTSC. All
6,600 fields (including residues), 360 native endpoint records and associated
geometry probes match. The final impulse-rejection guard is additionally
covered by `test_endpoint_owner_transactions_c.py`: 48 calls check invalid
initialization/span/tick, duplicate/gapped fields, failed controls after
private history advance, invalid final residue, impulse rejection, exhausted
intervals, preserved registers and atomic rejection. A 20-field sequence
checks fresh collective/engine/yaw/view inputs against native previews;
an inter-tick stick pulse changes fractional roll immediately. A recoil
applied before the next interval is captured in its anchor. Whole-tick and
PAL span entry checks also pass. This establishes the standalone owner, not
the remaining world-effect ordering or production responsiveness.

#### Scheduled endpoint publication

`timing-scheduled-endpoint.i` connects the airborne owner to delivered
scheduler records. Its 30-byte context binds owner, player, prepared stages,
sine helper, decoded packet and scheduler, plus the applied field and
per-call committed flag. It checks the delivered field/cutoff, display rate,
upcoming logical tick and ordinary command cursor; a due world deadline
also requires its world command cursor to be drained.

At an interval boundary it recovers the clock phase before the delivered
field and computes the number of fields to the next world deadline.
This selects PAL 17/17/16 and NTSC 20 without depending on render batching.
It rejects a new interval in the middle of an existing clock interval and
requires the owner's final field to coincide with `TS_DUE`.

Owner state and the player record remain private through native preview and
distribution. A second scheduler health check precedes publication. The
bridge then records its applied field/committed flag and acknowledges the
player step. A producer fault at acknowledgement retains the published
state and counts that field; recovery cannot repeat it. The caller still
owns decoded controls, world effects, ground handling and
lifecycle rebasing. This airborne bridge does not replace the older split
ground transaction or install a native main-loop hook.

`test_scheduled_endpoint_c.py` passes 960 delivered fields at 50/60 Hz with
batch sizes 1 and 25 (5,874 helper calls). All player records, residues,
history, interval spans and world-observation deadlines agree across batches;
the logical tick also crosses its word wrap. PAL delivers 14 deadlines per
240 fields and NTSC 12. The fixture observes deadlines and advances the
clock word; it does not execute the native world body.

`test_scheduled_endpoint_faults_c.py` passes 11 rejection cases and faults
injected before and after publication (124 helper calls). Cases cover
field/cutoff/rate/tick/phase/due mismatches, invalid controls/residue, upstream
faults and retained ordinary/world commands. Rejection leaves the owner,
player and scheduler completion count unchanged. A post-publication fault
retains committed metadata and exactly one completion, and clearing the
fault does not permit a replay.

#### Native yaw consumption at the deadline

Native +093F8 skips heading/yaw work when height is zero. Otherwise the
byte-negated pitch is compared unsigned with 4 at +09406. The hover branch
adds twice yaw to heading without clearing yaw; the other airborne branch
clears yaw at +0945A. This decision must use the native tick preview's
attitude and height, not a newly inferred condition on the distributed pose.

The endpoint player owner now copies the native candidate's yaw byte only
when its consumed-field count reaches the interval span. Before that field
it retains current yaw, so a command received during the interval can affect
subsequent motion. The scheduler bridge already requires that final field to
coincide with a world deadline. Yaw is published in the same transaction as
motion/history, so rejected work cannot consume it and a post-publication
fault cannot trigger another player step. No extra native motion call or RNG
draw is introduced.

`test_endpoint_yaw_c.py` passes 72 cases / 972 fields across whole-tick,
PAL 16/17 and NTSC 20-field intervals, zero/nonzero height and nine pitch
values including native signed-byte extremes. It compares the deadline byte
with native-preview output, verifies preservation on every earlier field,
and changes yaw during the interval. There are 24 native-clear and 48
native-retain outcomes. The 48-call owner transaction suite still passes.
The scheduler batch fixture now injects yaw changes every seventh delivered
field; all 960 fields remain batch-invariant and no non-deadline field
consumes yaw. The 124-call scheduler rejection/fault suite also passes.

#### Ground-capable native endpoint preview

Ground handling cannot simply be appended to the completed airborne endpoint.
Native +095A0..+09636 can reset vertical speed, forward speed, roll and pitch;
the subsequent +09636..+0979A arithmetic then calculates forward response,
horizontal displacement and RPM from that changed state. Clearing the fields
after the tail would omit those native results, and replaying the whole tail
without restoring its inputs could apply displacement or RPM twice.

`timing-endpoint-ground-preview.i` now composes the existing split native
player path and deferred ground handler as a transactional h=1 candidate
builder. Its eight-byte binding supplies the prepared deferred ground clone
and the event record bound into that clone. It rejects a pending event and
non-native preview rates, prepares through height, evaluates native ground
privately, then completes the native tail in order. Successful completion
publishes the private candidate and leaves a ready deferred event; failure
preserves the original candidate/state and discards the newly prepared event.
It does not notify native UI or write the native timer during preview.

`test_endpoint_ground_preview_c.py` compares 512 complete records and
eventual notification/timer outcomes against original clamp, controls and
native motion with ground restored. All match, including 31 notifications
and 309 zero-height endpoints (2,572 helper calls). Native disturbance RNG
is disabled and notification UI is represented by a call counter. Pending
events reject without replacement; invalid rate, control, logical tick and
component state reject without publication. A fresh-CPU injected failure at
completion, after ground has made its event ready, leaves player/state
unchanged, clears the event and produces no native effects.

This establishes a ground-capable endpoint candidate, not the distributed
player's contact policy. The owner must still select contact using committed
world-deadline state, reconcile endpoint contributions/fractions and publish
the selected event once. In particular, a speculative ground result from
an earlier field must not become an authoritative landing or crash. The
airborne scheduler bridge remains uninstalled and is not a complete ground
integration.
