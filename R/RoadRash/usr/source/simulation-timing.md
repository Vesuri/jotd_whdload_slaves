## Combined-model crash origin and collision-driven steering

`crash_origin_c.py` replays the original lap input through a known pre-crash
checkpoint, asserts that the player is still riding, then breaks immediately
before native writes that enter a crash state. Relocated movement-code sites
are mapped back to native addresses. The probe preserves field-timed controls;
B starts observing at 1300, the combined candidate at 1500 after releasing LEFT.

`b-crash-origin` reaches `$8e3b0` at live/simulation field **1374**, before
crash state 0 is stored. The usual sampled onset at 1376 observes that transition later.
The caller returns through `$8c450` in world-object collision handling; A0 is
object-record `$a7c8e`, A4 is handler `$8e35a`. Player lateral position is -468.
`c-combined-crash-origin` reaches the different object handler's `$8e4b8` at
live/simulation field **1537**, with A0 `$a7c3e`, A4 `$8e418` and lateral -902.
This is observed at 1538 by the two-field lap samples. Neither first crash is
entered through the rider-health or skid-threshold crash-state write. These
records identify object handlers and record addresses, not a decoded scenery
sprite identity.

The approach differs before either terminal collision. At field 1374, the
ordinary lap snapshots place B at position 11,792,110/lateral -468 and the
candidate at 11,817,279/lateral -385. B's snapshot can interrupt the collision
routine before its crash-state store, so it must not be treated as a completed
pre-contact state. Candidate lateral motion briefly reverses during the held-
LEFT turn. This prompted a separate probe of collision-driven steering writes.

`steering_contact_c.py` watches `$8c25e` and `$8c36c` for player A1 from field
1200 to 1400, while preserving the original held-LEFT input. All observed
writes occur at `$8c25e`, which replaces steering and actor `+$42` using the
current heading multiplied by 64. Results:

| Run | Simulation cursors | Other riders |
|---|---|---|
| `b-steering-contact` | 1253, 1265, 1286, 1302 | `$a6260`, then `$a61e0` three times |
| `c-combined-steering-contact` | 1256..1262 inclusive, 1309 | `$a6260` seven times, then `$a61e0` |

At the first contact, B's player/rival lateral positions are -107/+17, whereas
the candidate's are -176/-66. During the candidate's repeated contact its
player heading alternates 4/-51/7/-50/9/-50/13, repeatedly overwriting the
steering response despite LEFT remaining held. The different NPC approach and
contact sequence therefore need investigation before attributing the missed
scenery collision to road thresholds. The trace does not by itself prove that
per-tick collision frequency is wrong or justify adding a collision cooldown.
The existing private NPC lateral normalization is the next relevant component
to evaluate with the combined model; no runtime change is made here.

## Combined reference motion and road timing on the compact runtime

A private candidate combines the existing four-field endpoint displacement
correction with `VERIFY_C_ROAD_TIMING` on the newly integrated compact-geometry
runtime. It still advances one PAL field per tick, preserves velocity/input
updates, and introduces no arbitrary speed multiplier. It changes authoritative
movement and therefore requires comparison to B, not just self-equivalence.

`c-combined-motion-build/RoadRash.slave` is 19,624 bytes,
SHA-256 `35860a067eae178b4a8afd25e4c55321d52d60828d0a5951aff425dbd5adea03`.
Exact source deltas and the generator are retained in
`c-combined-motion-source/source.patch` and `make_combined_motion_c.py` under
the ignored harness. Tracked normal source is unchanged by this experiment.

| Cell | Distance @490 | Difference from corresponding B | fps |
|---|---:|---:|---:|
| Fast 020 default | 3,334,538 | -0.886% | 12.2 |
| Fast 020 Cache | 3,334,538 | -0.399% | 12.2 |
| Fast 020 NoCache | 3,315,004 | -1.467% | 7.2 |
| 060/50 | 3,334,538 | — | 23.0 |

All four functional runs pass. Default/Cache 020 meet the short distance
tolerance, but NoCache remains outside it and loses 0.4 fps against the current
runtime. This does not establish an overall improvement or close A4.

`c-combined-motion-dynamics` records 501 completed updates. All 500 consecutive
pairs match `max(0,new_speed + floor(3*new_speed/2) - floor(3*old_speed/2))`
exactly. At completed cursor 590, position is 3,868,569; at cursor 592 it is
3,888,007, versus B's 3,888,640 at cursor 590 after 492 applied throttle fields.
This 633-unit aligned gap supports the reference-integration explanation, but
is not the prescribed live-field comparison and does not waive its failure.

`c-combined-motion-lap` restores speed near B on the returning curve (9,714 at
field 800 and 12,009 at 1000). Nevertheless its first sampled crash is at 1538,
versus B's 1376 and the standalone road candidate's 1372. The final decoded
rank is 15. Improved early speed/road placement is insufficient to claim
collision or handling equivalence; the changed overtaking/collision sequence
still needs investigation.

Full snapshot builds use the previously tested register-preserving nearby
bridges to avoid WHDLoad patch-target reach limits. Their normal outputs are
byte-identical to the candidate above. `c-combined-motion-fixed` and
`c-combined-motion-vary` match all **1595** common completed hashes, all **15**
sound requests, and all six authoritative cursor-1457 snapshot ranges using
`c-attacks.json`. This establishes sampled render-cadence independence of the
changed model, not equivalence to the current runtime or B. No integration is
made pending NoCache cost/distance and handling resolution.

## Integrate simulation-only collision geometry

Normal builds and lean `C_SIMULATION` diagnostics now select
`C_COLLISION_GEOMETRY`. Full snapshot diagnostics retain explicit
`VERIFY_C_COLLISION_GEOMETRY` selection for reference reproduction. The compact
routine is initialized only after the existing Enhanced framerate/CPU/Fast gate;
rendering keeps native complete geometry. There is no new user option or pacing.

`c-collision-geometry-runtime-build/RoadRash.slave` is 19,040 bytes,
SHA-256 `e94f1aeb2f6ac8ac8da133d73bcfac299bf0a829e3fa9339bab526690edc8daf`.
The normal binary is byte-identical to the private normal candidate used in the
hardware/response/control tests. Its lean diagnostic is byte-identical to the
tracked diagnostic used for the copy and toggle-off probes. This connects the
integration to the measured binaries without extrapolating from changed code.

The original three-cell matrix plus `c-collision-geometry-remaining-matrix`
cover all 11 normal configurations. Default/Cache Fast 020 reach 12.0 fps,
NoCache 7.6, 030 default/Cache 16.6, 040 default/Cache 19.3, and 060 default/Cache
23.0. A500 and Chip-only A1200 retain 8.5/12.5 fps and exactly match all legacy
initial, field-590 and final snapshot fields from the previous runtime. The
separate 040/060 `c-collision-geometry-mmu` checks pass with TC `$8000` and CACR
`$80008000`; data-cache emulation is disabled and these provide no speed claim.
Default/NoCache 020 distance is 3,308,406, still outside B's tolerance. Other
accelerated samples are 3,318,164; optimization does not close A4.

`c-collision-geometry-visible` measures paired neutral/RIGHT captures at fields
300..307: **180/160/140/200/180/160/140/200 ms**, identical to the previous normal
runtime at every phase (median 170 ms). Estimates retain one-field capture
uncertainty; phase 303 remains 20 ms behind B. This optimization adds no measured
response regression, but does not resolve the outstanding B phase difference.

In addition to the successful-finish comparison below, the varying-cadence
`c-collision-geometry-arrest` and `c-collision-geometry-wreck` preserve respectively
**8377/11945** completed hashes, **241/120** sound requests, all six authoritative
terminal ranges and exit fields **8378/11946** against the current physics/AI
references. Both restart with capture `(92,91,0,1)`. These use the original
recorded input tapes, with no synthetic damage or terminal-state seed.
The inspected final images confirm BUSTED and WRECKED respectively.

`c-collision-geometry-smoke` passes keyboard and CD32 steering/release,
pause/resume (active field held at 161), demo fire exit and natural timeout,
then enters a normal race after each demo. Stack guards remain intact; measured
high-water use is 256/356 bytes for keyboard/CD32 and 300 for both demo tests.
These are tests of the byte-identical normal candidate now integrated above.


## Collision geometry: full finish, cadence and disabled-path checks

`c-collision-geometry-finish` replays the retained
`c-steering-finish-lane/driven-tape.json` with the tracked diagnostic and a
four-field rendering floor. Against `c-physics-aux-finish`, all **12,822**
completed actor hashes, **24** sound requests, six authoritative terminal
ranges, finish at **12634**, and exit at **12823** match. A new race starts with
capture `(97,96,0,1)`. The inspected final image shows FINISHED and rank 01;
the next-race image has the expected road, riders, scenery and HUD.

`c-collision-geometry-finish-vary` uses the identical input tape with the
existing varying rendering pattern. It matches every hash, sound request,
terminal range and finish/exit boundary above, and starts a new race with
capture `(95,94,0,1)`. Actual frame intervals include 2, 3, 4, 12 and 16 fields
(counts 743/385/565/283/283, plus startup entries); the fixed run records 3207
four-field frames plus startup entries. Both runs cover airborne movement
and all crash states 0..4 in sampled steering coverage. The fixed run samples
two skid flags; the varying run samples none (their completed-tick hashes still
match). These are
functional-speed runs, not throughput measurements or full-draw 50 fps proof.

`c-collision-geometry-copy` verifies all **388** relocated bytes at `$9f8560`,
including the adjusted DBF displacement, against the two native spans. The
native rendering entry retains `LEA $a6f3c,A0`. The diagnostic is in Fast RAM.
`c-collision-geometry-off` uses the tracked lean diagnostic with `CUSTOM2=0`
and confirms original instructions at all 33 existing enhancement hook sites.
Normal production output remains unchanged.

This closes successful-finish/restart and the tested varying-cadence comparison
for this candidate. Arrest/wreck transitions, broader hardware/MMU coverage,
visible-response phases and gameplay/presentation review remain required before
normal integration. The existing B distance/handling differences remain open.

## Compact collision geometry on the current runtime

The earlier collision-only road experiment is retested after integration of
Fast RAM physics/AI. It copies `$8970e..$8984d` and `$8989e..$898e1` into a
388-byte Fast routine, omitting width and both edge projections only for the
simulation's collision-preparation call. Centre, height and occlusion remain;
native rendering still executes the full geometry routine. The sole relative
branch crossing the omitted span is adjusted from `$ff14` to `$ff64`.

`c-current-collision-geometry-matrix` measures the private 19,040-byte normal
candidate against the current normal-runtime matrix:

| Configuration | Current fps | Compact fps | Compact distance @490 |
|---|---:|---:|---:|
| Fast 020, default caches | 11.9 | 12.0 | 3,308,406 |
| Fast 020, NoCache | 7.0 | 7.6 | 3,308,406 |
| 060/50 | 22.8 | 23.0 | 3,318,164 |

All three functional checks pass. Unlike the earlier lean-runtime experiment,
these measurements improve throughput, especially NoCache (+8.6%). They do not
prove which phase/cache interaction changed. Both 020 distances are still
outside B's 1% tolerance and lower than the current normal runtime. Functional
pass is not A4 acceptance.

`c-current-collision-geometry-fixed` matches the fresh matched
`c-current-lut-reference` (despite its name, that reference has no lookup): all
1595 completed actor hashes, all three sound requests and all six authoritative
snapshot ranges at cursor 1457 agree. RNG and the attack tape are identical;
the diagnostic render floor is four fields. The in-flight final hash is excluded.

Retain the candidate in `collision_geometry.s` under
`VERIFY_C_COLLISION_GEOMETRY`, requiring C simulation and VERIFY. It rejects the
separate road relocation and width lookup combinations. Initialization occurs
only after the Enhanced framerate/CPU/Fast gate and flushes caches after copying.
The default normal binary remains byte-identical to the current runtime.
Tracked lean and full diagnostic builds are byte-identical to the corresponding
private tested builds (`c-collision-geometry-tracked-build` and
`c-collision-geometry-tracked-fixed-build`). No normal integration is made yet:
full-course/restart, cross-cadence, all-CPU/MMU, disabled-path, visible-response
and presentation checks remain necessary. This candidate does not resolve the
outstanding handling or distance differences.

## Current-runtime exact road-width lookup retest

`c-current-cost-audit` profiles the current 18,592-byte enhanced normal slave on
cycle-exact Fast 020 over fields 100..600. The road geometry routine
`$8970e..$898e1` accounts for 5.821% of flat recorded units, with 619 calls
(simulation preparation plus rendered frames). Its constant-width division at
`$89854` executes 19,808 times and accounts for 0.494%. These are flat profiler
units for this workload, not inclusive hardware timing or a universal cost split.

Retest the existing exact `VERIFY_C_GEOMETRY_LUT` with the current physics/AI
copies. The private normal source enables the flag for normal/C_SIMULATION
builds only; the tracked runtime remains unchanged. It reserves 40 KiB optional
ExpMem rather than 20 KiB and uses the existing gated, exact 8193-word lookup.
Candidate `c-current-lut-build/RoadRash.slave` is 18,696 bytes,
SHA-256 `d26613ddea22e611a7257c34af896f38796d0d93f4b82dcad49ef3c9649a9df4`.

| Normal configuration | Current runtime fps | Lookup candidate fps | Candidate distance at 490 fields |
|---|---:|---:|---:|
| Fast 020, default caches | 11.9 | 12.4 | 3,318,164 |
| Fast 020, NoCache | 7.0 | 6.9 | 3,318,164 |
| 060/50 | 22.8 | 22.8 | 3,318,164 |

All three `c-current-lut-matrix` cells pass their functional checks. The cached
020 gain is 4.2%; it is not a universal improvement, and the flat division cost
alone does not explain the whole throughput change. Frame deadlines and code
layout can affect the result. The distance remains outside the default/NoCache
B tolerance. No promotion to the normal runtime follows from these measurements.

`c-current-lut-fixed` and `c-current-lut-reference` use fresh matched builds,
seeded RNG, `c-attacks.json`, a four-field diagnostic presentation floor and
capture cursor 1457. All **1595 completed actor hashes**, all **three sound
requests**, and all six authoritative snapshot ranges match. The final in-flight
hash is excluded. These checks establish short-tape equivalence for the retest;
full-race/restart, cadence, cache/MMU, fallback and latency validation would still
be required before any integration. Earlier lookup evidence is retained below.

## Native rank audit: stale off-screen positions invalidate the old order check

### Enhanced comparisons and publication-boundary validation

The same observation on `c-road-rank-audit` and `c-npc-rank-audit` covers all
15 racers exactly once across active/ahead/behind lists at all 23 sampled
boundaries in each run. Neither substitutes a sorted off-screen stack for a
complete race order. The decoded HUD ranks differ from B as follows:

| Field | B | Road correction | NPC lateral prototype |
|---|---:|---:|---:|
| 1140 | 14 | 15 | 15 |
| 1200 | 14 | 15 | 14 |
| 1300 | 14 | 13 | 13 |
| 1460 | 15 | 13 | 13 |
| 1500 | 15 | 14 | 14 |

At 1140 the road candidate still has rider `$a6260` 3409 position units ahead;
B has that rider 20989 behind. At 1300, `$a61e0` is 1018 behind in the candidate
and 10 ahead in B. These are nearby-rider differences, not artifacts of sorting
inactive positions. The NPC prototype does not restore the sampled B rank
sequence or crash behavior.

The road candidate's field-1200 snapshot reconstructs rank 14 while its stored
HUD rank is still 15. A field stop can interrupt a simulation step between
movement and rank publication. `c-road-rank-boundary` therefore stops at
`$8936c`, immediately after the native rank store, through simulation cursor
1202. All **55** observations match reconstructed and decoded rank. The rank
formula is validated at that boundary; an arbitrary field-boundary mismatch
must not be called a gameplay bug without checking publication timing.

The shared ignored `harness_a.py` now retains legacy raw `rank` and stored-
position `order` for old-capture compatibility, adds `rank_displayed` and
`native_ranking` (ahead/behind membership, reconstructed and displayed rank,
and the mid-simulation observation caveat), and validates the complete rider
partition. `replay_a.py` prints the decoded rank. Legacy raw-state hashes and
comparison inputs are unchanged; this does not silently turn failed comparisons
into passes. `c-road-native-ranking-harness` reruns the enhanced lap and
preserves every legacy field, including state hashes, in all 24 snapshots
(initial plus 23 scheduled samples). Full opponent-order equivalence remains
an open verification task.


The A4 harness's `order` field sorts all 15 riders by their stored actor `+4`
positions. This is not the game's complete race order: inactive riders stop
updating those positions. Do not use prior `order` mismatches alone as evidence
of a race-order regression, or treat their removal as an A4 pass. Existing raw
captures remain unchanged for reproducibility; full order equivalence is still
unproven.

Native `$892a0` computes the player's rank from the count at `$90946` (inactive
riders ahead, excluding cop `$a5de0`), plus active riders in `$909cc` whose
unsigned positions exceed the player's, plus one. `$89356..$89366` converts
10..15 to packed decimal before storing `$a59f4`. Earlier reports of rank 21
therefore mean raw `$0015`, displayed **15th**, not 21st; raw 20 and 19 mean
14th and 13th. Equality checks of the raw rank remain meaningful.

The ahead/behind arrays at `$90946`/`$90988` are counted pointer stacks:
`$90d04` appends and `$90d12` removes the last entry. Their internal order is
not a proven positional ranking. `$90ac0` estimates inactive progress using
actor `+$66` multiplied by the low word of the simulation cursor at `$a5d52`.
A replacement full-order verifier must account for this model rather than
merely concatenate or sort the arrays.

Live evidence: `tmp/dev/tmp/b-rank-audit-v2/replay.json`, produced by
`tmp/dev/tools/rank_audit_c.py` with the retained B normal slave, A1200 Fast,
`CUSTOM2=3`, and the original lap tape at 100-field sample spacing plus tape
and screenshot boundaries. All **23** audited samples reconstruct exactly the
decoded stored rank. All 23 disagree with the rank inferred by sorting stored
positions. At field 100 the native rank is 15 while the old position sort says
8; at field 1600 native rank is 15 while the sort says 6. The wrapper adds
`rank_audit` with both inactive lists, reconstructed rank, decoded rank and old
position-sort rank without changing the legacy fields or comparisons. This is
a sampled pre-finish validation, not proof about terminal ranking behavior.

The preceding NPC lateral prototype remains private. Quarter-reference
integration improves rival `$a61e0` at fields 600/1000/1200 from lateral
-15/-103/-187 to 4/18/5 versus B's 4/11/4, but moves the sampled player crash
onset from road correction's 1372 to 1544 versus B's 1376. Evidence remains in
`c-npc-lateral-lap`, `c-npc-lateral-leaders` and the retained build's source
patch. Neither this prototype nor the rank-audit finding closes handling,
distance, throughput or input-response acceptance.

# Simulation/presentation separation audit

C is in progress. The normal beta now uses the shared independent simulation
on supported hardware when Enhanced framerate is enabled. Runtime integration
and remaining regression/latency checks are not yet a completion claim.
Addresses follow performance-plan.md's absolute-address convention.

## Current runtime: combined Fast RAM AI and acceleration helpers

Normal and lean builds now also select `C_PHYSICS_AUX`; full diagnostics
opt in with `VERIFY_C_PHYSICS_AUX`. The four audited spans below add 2,356
copied code bytes and eight entry redirects. Initialization remains inside
the existing Enhanced framerate/CPU/Fast gate. Native data and the simulation
timestep remain unchanged. Two movement-code stubs call copied helpers directly.

The normal slave is 18,592 bytes, SHA-256
`4a6a5d667acaf0462ead705b5a342e5f6de8449e2fbe3dedb7bef638b82a966f`.
Tracked-source normal, full and MMU binaries are byte-identical to the tested
`c-physics-aux-runtime-build`, `c-physics-aux-full-build` and
`c-physics-aux-runtime-mmu-build` variants respectively.

`c-physics-aux-runtime-matrix` passes all 11 normal configurations:

| Configuration | Previous fps | Current fps |
| --- | ---: | ---: |
| A500 | 8.5 | 8.5 |
| Chip-only 020 | 12.5 | 12.5 |
| Fast 020, default | 10.3 | 11.9 |
| Fast 020, Cache | 10.2 | 11.9 |
| Fast 020, NoCache | 6.3 | 7.0 |
| 030, default/Cache | 16.6 | 16.6 |
| 040, default/Cache | 18.8 | 18.9 |
| 060, default/Cache | 20.7 | 22.8 |

A500 and Chip-only 020 initial, field-590 and final state hashes remain exact.
Both enabled-MMU functional cells pass with CACR `$80008000`.
`c-physics-aux-runtime-off` checks all eight new entries in addition to the
previously covered hooks. `c-physics-aux-runtime-probe` verifies the normal
copy, all 30 branch adjustments and the three movement-code branches that
reach the two direct helper stubs.

`c-physics-aux-{finish,arrest,wreck}` match their steering references across
12,822/8,377/11,945 completed hashes, 24/241/120 sound requests, all six
terminal authoritative regions, and terminal times. All three restart with
`[99,98,0,1]`. The varying-cadence attack comparison below also passes.

Normal keyboard/CD32 steering, release, pause and resume pass in
`c-aux-runtime-{input,pad}`; stack use is 284/332 bytes with intact guards.
The fire and timeout demo checks exit at fields 507/3,598 and both enter
a normal race at field 100. Their stack use is 288/308 bytes with intact
guards. The resulting race screenshots were inspected.

`c-physics-aux-runtime-visible` measures 180/160/140/200/180/160/140/200 ms,
median 170 ms. The first three phases match the preceding runtime; the
remaining five improve by 20–40 ms. Against B, six phases improve, one
matches, and phase 303 still trails by 20 ms. Capture-end estimates have
one-field resolution and do not prove all-phase equivalence.

The accelerated matrix's live-field distance is now 3,318,164 in every cell.
Default Fast 020 and NoCache remain 1.373% below their B references; the
Cache 020 and all 030/040/060 cells are within 1%. Handling/rank/crash
equivalence remains unresolved. Throughput is closer to B but still below
it in several configurations. These improvements do not complete C.

### Current distance accounting and reference-integration candidate

`c-aux-distance-dynamics` traces completed ticks in the current normal runtime
with default cache policy. `b-default-distance-dynamics` runs the preserved
B normal binary with CUSTOM2=3 and its original default cache policy. Both
receive throttle at live field 100. Every B step in this window uses delta 4.

At completed cursor 590, B is at 3,888,640 and C at 3,852,194. The actual
live-field C checkpoint still contains cursor 589, position 3,842,452.
The 46,188-unit live-field gap can be decomposed without changing either run:

| Component | Distance units |
| --- | ---: |
| C cursor 589 to completed cursor 590 | 9,742 |
| C cursor 590 to 592, equalizing applied throttle fields | 19,437 |
| B four-field end-speed integration versus unit interpolation | 14,568 |
| Remaining aligned difference | 2,441 |

B has applied 492 throttle fields by cursor 590, starting with speed 136
and displacement 544 at cursor 102. C first moves at cursor 101, speed 34
and displacement 34. Its cursor-592 position is 3,871,631. For each
four-field B step, using its end speed over the whole step exceeds unit
linear velocity integration by `3/2 * (end_speed - start_speed)`. Summed
over this window, that is `3/2 * 9712 = 14568`. This is an accounting
counterfactual over B's recorded steps, not proof that intermediate gear
or terrain states would remain identical. The raw live-field acceptance
failure remains; the aligned comparison does not replace it.

A private `REFERENCE_MOTION` experiment tests preserving the four-field
endpoint convention while continuing to advance one tick per active field.
In the primary movement loop it captures velocity before the native update
and sets displacement to:

`max(0, new_speed + floor(3*new_speed/2) - floor(3*old_speed/2))`.

For constant acceleration without clamping, four such updates sum to the
native four-field end-speed displacement. Differencing the rounded offsets
preserves half units without persistent per-actor fractional state. The helper
does not write velocity or change tick count or input sampling; altered
positions can affect later terrain and velocity decisions. Other paths that
override this displacement, including special crash paths, have not been
normalized by this prototype. This is a gameplay change, unlike code copying;
old authoritative trajectory hashes are not expected to remain equal.

`c-reference-motion-dynamics` checks 500 completed primary updates against
the formula and their resulting position increments. Completed-cursor-590
distance is 0.707% below B, versus the current runtime's 1.083%.
The actual normal-candidate live-field measurements in
`c-reference-motion-runtime-020` are:

| Fast 020 policy | Distance | Difference from B | fps |
| --- | ---: | ---: | ---: |
| Default | 3,330,871 | -0.995% | 12.0 |
| Cache | 3,330,871 | -0.509% | 12.0 |
| NoCache | 3,321,166 | -1.284% | 6.8 |

The first two pass the distance gate, narrowly in the default case. NoCache
still fails and loses 0.2 fps against the integrated runtime. The prototype
is therefore not promoted. Its normal binary is 18,696 bytes, SHA-256
`f12150a0710da2b9aaa07f605975bafb891d011f11d84748d580c5d459cec2c0`.

The first full diagnostics failed before entering the game because their
new PL_P targets exceeded WHDLoad's signed patch-target reach. The retained
v2 builds use nearby register-preserving bridges to the same motion helper.
`c-reference-motion-period4-v2` and `c-reference-motion-varying-v2` match
1,595 conservatively completed hashes (excluding the last counted tick),
three sound requests and all six authoritative field-1,457 regions. This
proves the sampled cadence independence of the candidate, not B-equivalent
handling or full-race acceptance. The source deltas are retained in
`c-reference-motion-build/source.patch` and
`c-reference-motion-period4-v2-build/source.patch`; normal source is unchanged.
Further work must reduce the candidate's cost and cover the remaining
movement paths, full-race outcomes and response phases before integration.

### Compact correction tests and the longer lap discrepancy

Two private variants retain the same displacement formula. The compact version
saves old velocity in a two-byte stack slot between the hooks, replacing the
global scratch word and its A0 save/restore. The native update between those
hooks has no calls or exits: both acceleration branches join at `$8b4d2`.
The correction uses `floor(3*v/2) = v + floor(v/2)` to reduce arithmetic.
The aligned variant saves the adjacent actor words in a four-byte slot and
reads its speed half, preserving the incoming stack alignment instead.

`c-reference-motion-compact-varying` matches the earlier formula's fixed-period
reference across 1,595 conservatively completed hashes, three sound requests
and all six authoritative field-1,457 regions. The shorter code does not
produce a useful throughput improvement:

| Fast 020 policy | Compact fps | Four-byte-slot fps | Distance, both |
| --- | ---: | ---: | ---: |
| Default | 11.8 | 11.9 | 3,321,166 |
| Cache | 11.8 | 11.9 | 3,321,166 |
| NoCache | 6.8 | 6.8 | 3,301,708 |

Against B these distances differ by -1.284%, -0.798% and -1.862% respectively.
The four-byte-slot result isolates a small cached improvement within this
equal-size layout, but does not prove that stack alignment alone caused it.
Neither variant closes the default/NoCache gates. The original larger helper
had a more favorable sampled phase; reducing instruction count did not
preserve that advantage.

Both normal candidates are 18,676 bytes. Compact SHA-256:
`264625a71035c1b6e1e1a2a5f665db56d14fca7f4cadfb5e4cccc64bc8b657fb`;
four-byte-slot:
`31bfa48b9522a51e3b6a392922775b6781440f3b1bcdf167d8757ec917538629`.
Their build directories retain exact source deltas. Neither is promoted;
the aligned variant has not received the compact variant's replay acceptance.

The original A1b lap tape is now also replayed on the current normal runtime
in `c-aux-runtime-lap` and on the compact candidate in
`c-reference-motion-compact-lap`. Both end with rank 21 and one sampled crash,
as does `b-final-replay-on`, but the complete opponent orders differ.
Crash onsets are 1442/1444 for current/candidate C versus B's 1376.
Thus the distance correction does not close A4 handling equivalence.

The trace identifies a larger divergence after the first steering input:
at field 800 B's player speed is 9,772 with flags `$4200`, while current C
is at 7,710 with `$4a00` and corrected C at 7,700 with `$4a00`.
Bit 3 of actor `+$68`, set by the native road-relative lateral bounds check,
therefore still marks both C players off-road when B is back on the road.
By field 1000, B travels at 12,024 versus 7,099 in both C variants.
Their positions are 8,005,924 / 7,084,951 / 7,096,105 respectively.
This much larger later difference cannot be resolved by the small endpoint
correction alone. The next investigation should trace road-centre/relative
position across the returning curve and steering input, including positive
curve updates. The earlier road-operand audit covered the initial negative
curve and does not establish equivalence through this later section.

### Returning-curve road-relative trace

`b-reference-road-lap` and `c-aux-road-lap` repeat the unchanged field-scheduled
lap tape, adding read-only player road-centre and road-relative snapshots.
The B run reproduces all 752 prior sampled state hashes. C reproduces every
sampled speed, lateral position, rank, opponent order and crash state; one
position sample (1326) and two flag samples (1188/1486) differ, so this is not
an exact whole-state replay claim. The checkpoints below reproduce the earlier
player position/speed observations.

| Field | B road centre | C road centre | B centre minus lateral | C centre minus lateral |
| --- | ---: | ---: | ---: | ---: |
| 600 | -105 | -102 | -265 | -262 |
| 700 | -33 | -111 | -250 | -325 |
| 800 | 63 | -111 | -126 | -305 |
| 900 | 96 | -111 | 15 | -226 |
| 1000 | 0 | -114 | -85 | -229 |

This directly locates the later slowdown in the returning road-centre motion:
C does not recover the positive centre movement that brings B inside the
native +/-224 road-relative bounds. At field 700 the native road update word
at player +$38 is positive in both runs (B 2, C 6), while C's centre is still
negative. Positive small-step truncation is the next hypothesis to test at the
actual integration instruction; these snapshots alone do not establish the
operand-level cause. No motion correction or new runtime patch is promoted.
The comparison is retained in `c-aux-road-lap/comparison.json`.

### Curve integration operand audit

`b-road-return-operands` and `c-road-return-operands-v2` trace the player
integration after the original tape's field-600/620 right-steering input.
The first C attempt targeted the native address and timed out; the corrected
trace resolves the Fast RAM copy through the `$8b486` entry redirect.
Every captured centre transition is checked against the preceding arithmetic.
The native update is `3 * floor(floor(displacement/256) * d6 /256)`;
`d6` is a change in the interpolated track curve, not an independent fixed
curve coefficient. Thus both factors depend on the step length.

B records 41 updates through cursor 783, curvature changes totalling 125,
and centre movement +162. C records 162 updates through cursor 780,
curvature changes totalling 114: 114 increments of one and 48 zeroes.
Every C product rounds to zero. This proves the returning-curve loss at the
integration instruction, not just from sampled player flags. The intervals
and trajectories differ slightly, so their totals are not an exact aligned
physics comparison.

The private `c-road-reference-source` experiment evaluates displacement and
curvature change at four times their unit-step values, runs the native signed
rounding, then carries quarter-unit output into the road centre. It restores
positive motion, but overcorrects: road centres at fields 600/800 are -78/+146
versus B -105/+63; its crash occurs at 1330 versus B 1376. It is rejected for
integration. Its normal binary is 18,692 bytes, SHA-256
`e54e2b682149d0e95d1605dc48a9d7a491abb8da176132c716b695728c9c82ae`.
Exact private source changes are retained in its build directory. Multiplying
an already-rounded one-field curvature change is insufficient to reproduce
the original reference calculation.

The follow-up `c-road-window-source` substitutes the sum of the current and
three preceding curvature changes for `4*d6`, retaining the four-field
reference displacement and quarter-unit carry. History and carry reset with
simulation state. It still executes every simulation field; there is no
render wait or delayed presentation buffer. This is a private numerical
integration experiment, not a change to the accepted runtime.

`c-road-window-lap` brings road centres much closer to B:

| Field | B centre | Candidate centre | B position | Candidate position |
| --- | ---: | ---: | ---: | ---: |
| 600 | -105 | -102 | 3,965,632 | 3,933,461 |
| 800 | 63 | 54 | 5,761,316 | 5,730,305 |
| 1000 | 0 | 10 | 8,005,924 | 7,936,097 |
| 1200 | -183 | -184 | 10,124,359 | 10,087,294 |

However, the later trajectory still fails: at field 1300 the player's lateral
position is -427 versus B -172, with similar road centres (-158/-156).
The sampled crash begins at 1324 rather than 1376 and final rank is 20 versus
21. This isolates a remaining later handling difference after correcting
most of the road-centre error; it does not establish a cause for that later
difference. The next comparison should trace steering, skid/collision state
and lateral increments around fields 1140–1324 with this candidate.
The binary is 18,728 bytes, SHA-256
`e3da1a13a4d0ea0ad15c6565700625e1b154f3ff290f8b01a7494bdb599f54d5`;
its build directory retains the source patch. Neither cadence equivalence,
full-race acceptance nor the hardware/performance matrix has been run for it.

### Later steering divergence: opponent road integration

The extended `b-reference-lateral` / `c-road-window-lateral` snapshots show
that B's heading repeatedly approaches zero after field 1250 while left
remains held. `b-lateral-collision-writes` then traces four writes at `$8c266`,
at fields 1253, 1265, 1286 and 1302, involving actors `$a6260` and `$a61e0`.
These collision paths reset the steering accumulator `$a7262`.
`c-road-window-collision-writes` sees no corresponding writes through 1325.
Both traces schedule the original inputs through 1140 and stop at race-field
boundaries, resolving relocated collision addresses in C.

`b-reference-rivals` / `c-road-window-rivals` locate the preceding opponent
error. At field 800 actor `$a61e0` has road centre +54 in B versus +249 in C;
at field 600 it was -54 versus -213. By field 1250 its C position trails the
player by 3,678,751 units, whereas B's actor is 27,228 units ahead. The missing
player collisions therefore cannot be repaired solely by changing player
steering arithmetic.

The native opponent road routine differs from the player's: at `$8bcd0` it
adds the interpolated curve value `d1` directly to actor `+$36` on every call.
It computes a curve difference in `d6` immediately beforehand but does not use
that difference for this addition. This is a per-call accumulation requiring
normalization independently of the player's displacement-product correction.

Private `c-road-actors-source` adds a separate quarter-unit carry for each of
35 actor records. A hook at `$8bcd0` adds one quarter of the native signed value
per one-field tick, preserving the remainder and replaying the displaced
following instruction. The table clears with simulation state; actor addresses
outside the native table fall back to the original addition. This candidate
also retains the player's four-tick curve history from the previous experiment.
Actor-slot reuse/remount carry lifecycle and the reverse-travel routine remain
to be audited before integration.

`c-road-actors-lap` improves the original lap substantially:

| Field | B player position | Candidate position | B rival centre | Candidate rival centre |
| --- | ---: | ---: | ---: | ---: |
| 600 | 3,965,632 | 3,933,461 | -54 | -54 |
| 800 | 5,761,316 | 5,730,305 | 54 | 61 |
| 1000 | 8,005,924 | 7,948,095 | 16 | 27 |
| 1200 | 10,124,359 | 10,087,294 | -31 | -27 |
| 1300 | 11,023,526 | 11,037,597 | -16 | -11 |
| 1600 | 13,031,078 | 13,138,349 | -13 | -73 |

The sampled player crash is now 1372 versus B 1376; both finish rank 21 with
one crash. The complete opponent order still differs, including `$a6360` and
`$a63e0`, so A4b is not passed. These are normal unseeded baseline comparisons,
not proof that every AI difference is attributable to this arithmetic alone.
The 18,952-byte candidate SHA-256 is
`1c95b8dba97ff7ab684e03ac4aff34cb6b264ead687e3c597599b585ad486f0c`.
Its build directory retains the source patch. The next gates are completed-tick
cadence equivalence, carry lifecycle/reverse-path audit, and normal hardware
throughput/distance checks before any runtime promotion.

### Road correction cadence check and lifecycle audit

The unmodified private actor-road candidate now passes the controlled-seed
attack tape at requested period 4 versus varying/long rendering intervals:
`c-road-actors-period4` and `c-road-actors-varying` match 1,595 conservatively
completed actor hashes, ten sound requests and all six authoritative regions
at capture field 1457. The actual frame histograms differ: the first run has
280 frames with ordinary intervals mostly 4–8 fields; the varying run has
170 frames and intervals reaching 20 fields. This verifies catch-up invariance
under those measured schedules, not exact 1/2/3-field presentation coverage.
The comparison is retained in the varying run's `comparison.json`.

The new fractional state still needs lifecycle work. Native `$8bdc8` copies a
complete actor record to its companion through the `$941ea` pointer table,
but the candidate's external quarter-unit carry is not included. The native
initialization clears actor road fields at `$87eb4` onward. The candidate does
clear all carries during simulation reset, but has no actor-copy hook.
The player's three prior curvature changes also survive a crash: the existing
`step_steering_finish` clears only lateral steering carry. These omissions
must be resolved and tested through crash/remount and race restart before
runtime integration.

The reverse routines at `$8be02` and `$8bf06` subtract the sum of crossed
track segments from road centre (`$8bec6` / `$8bfb6`), rather than adding the
forward routine's interpolated value every call. Applying the forward /4
correction to these instructions would therefore change a spatial increment
incorrectly. Reverse transitions still need lifecycle coverage for the new
forward-history state.

The candidate also completes all eleven normal hardware cells in
`c-road-actors-020` and `c-road-actors-rest`. A500 and Chip-only 020 initial,
field-590 and final hashes exactly match the preceding runtime. Throughput is:

| Configuration | Candidate fps | Preceding runtime fps |
| --- | ---: | ---: |
| A500 | 8.5 | 8.5 |
| Chip-only 020 | 12.5 | 12.5 |
| Fast 020 default / Cache | 11.8 | 11.9 |
| Fast 020 NoCache | 6.7 | 7.0 |
| 030 default / Cache | 16.6 | 16.6 |
| 040 default / Cache | 18.9 | 18.9 |
| 060 default / Cache | 21.8 | 22.8 |

Accelerated distance is 3,321,603 except 020 NoCache at 3,311,794. Against B,
020 default differs by -1.271%, Cache by -0.785%, and NoCache by -1.562%.
Thus the improved lap handling does not close the short-window distance or
performance gates. No MMU, full-race transition, or visible-latency acceptance
is claimed for this candidate. It remains private and unpromoted.

### Private road-state lifecycle repair

`c-road-lifecycle-source` extends the preceding private candidate in two places.
At native `$8bdf0`, after companion-record copying has restored A0/A1, a hook
copies the external per-actor road carry alongside the native record. It checks
that both pointers name aligned records in the 35-record table; an in-table
destination with an out-of-table source is cleared. The hook preserves its
working registers and replays the displaced height shift and `$8b484` store.
At the completed-step crash boundary, `step_steering_finish` now clears the
player's road carry and three historical curvature changes as well as its
existing lateral carry. Both additions remain within the enhanced patch path.

`c-road-lifecycle-period4` and `c-road-lifecycle-varying` match 1,595 completed
hashes, ten sound requests and all six field-1457 authoritative regions.
These hashes also match the preceding actor-road candidate on this short tape;
that fact alone does not exercise nonzero companion carry transfer.

The direct natural copy probe observes player `$a5d60` copied to companion
`$a6560` at field 1029, with zero carry on both sides and unchanged D0–D2/A0–A2.
An attempted debugger-injected nonzero test failed because memory readback
showed that the debugger writes had not taken effect. Those runs are retained
as failed test setup, not evidence of a faulty copy hook or successful injection.
A separate diagnostic binary seeds source carry 3 and destination carry 1 in
its reset routine. `c-road-lifecycle-copy-seeded` then verifies the real copy
changes destination to 3 and preserves the same registers. Its seeds are not
present in the candidate binary.

`c-road-lifecycle-crash-natural` starts from naturally nonzero history
`00000000fffefffffffe0000` and verifies that the real crash boundary clears
all twelve bytes. No debugger writes are used for this acceptance. This
supersedes the earlier crash probe's unverified injection label.

The unseeded normal lifecycle candidate is 19,076 bytes, SHA-256
`976ef0d2adcbcde99c9b310e597117388e87ba0a20070a6b74a009287c3fce90`.
Its period4 build directory retains the complete source delta. Full-race
finish/arrest/wreck and restart coverage, reverse/slot-reuse transitions,
normal lap, hardware costs and remaining A4 differences still require checks
before promotion. The production runtime remains unchanged.

### Reproducible road diagnostic and full-race coverage

The road correction and lifecycle helpers are now retained in `road_timing.s`,
selected explicitly with `VERIFY_C_ROAD_TIMING` alongside normalized steering.
They are not selected by normal builds. All associated patch sites remain in
the Enhanced framerate/CPU/Fast gated simulation patch list. This makes the
experiment reproducible without promoting its unresolved A4/performance costs.
The tracked period4 and varying full-diagnostic builds are byte-identical to
the tested private lifecycle binaries. The normal build remains 18,592 bytes,
SHA-256 `4a6a5d667acaf0462ead705b5a342e5f6de8449e2fbe3dedb7bef638b82a966f`.

Two newly recorded field-timed tapes now cover full-race exits and restarts on
the lifecycle candidate, using functional-speed 020 diagnostics:

| Outcome | Reference / varying replay | Completed hashes | Sound requests | Finish field | Exit field |
| --- | --- | ---: | ---: | ---: | ---: |
| Arrest | `c-road-lifecycle-driven-v2` / `c-road-lifecycle-replay-vary` | 6,885 | 78 | none | 6886 |
| Finish | `c-road-lifecycle-lane-drive` / `c-road-lifecycle-finish-vary` | 16,454 | 67 | 16266 | 16455 |

Each pair matches every published completed-tick hash, all sound requests,
terminal timing and all six authoritative terminal regions. Both tapes exercise
crash states 0–4, riding/remount, and airborne state; lateral carry remains
within the configured quarter-unit bound. Restart probes read the twelve player
road-state bytes and 140 actor-carry bytes and verify they are all zero after
entering the next race. Final screenshots were inspected and show BUSTED and
FINISHED respectively. These results establish cadence equivalence for the
candidate, not equality to the preceding runtime or B's different trajectories.

The initial full-race launch failed in AmigaDOS because CUSTOM2 was supplied
twice; its screenshot and output are retained as `c-road-lifecycle-driven`.
The harness now avoids appending a duplicate option. The normal-build original
lap rerun (`c-road-lifecycle-lap`) retains crash onset 1372, final rank 21 and
position 13,138,349, with the same final racer order as the preceding candidate.
Intermediate live-field samples are not all identical; they are not substituted
for the completed-tick comparison above.

Wreck-exit coverage, shorter exact render periods, remaining reverse/actor-slot
lifecycle cases, the final candidate's hardware/MMU/control/latency checks and
B-equivalence/performance gaps remain open. Section C is not complete.

### Road diagnostic: exact short presentation intervals

Functional-speed 020 runs now exercise the short schedules explicitly with
`VERIFY_C_ROAD_TIMING`, the seeded attack tape and capture field 1457:

| Run | Requested interval | Measured ordinary intervals | Frame count |
| --- | ---: | --- | ---: |
| `c-road-period1-functional` | 1 | 799 at 2 fields | 803 |
| `c-road-period2-functional` | 2 | 799 at 2 fields | 803 |
| `c-road-period3-functional` | 3 | 533 at 3 fields | 537 |
| `c-road-period4-functional` | 4 | 399 at 4 fields | 403 |
| `c-road-period1-skip` | 1, drawing omitted | 1,600 at 1 field | 1,603 |

Counts include three initial zero-interval samples and, except the skip run,
one initial one-field sample. The nominal period-1 full-drawing run does not
reach one-field presentation; it must not be counted as that coverage.
The existing `VERIFY_SKIP_RENDER` diagnostic provides the actual one-field
case, preserving simulation work and the native presentation handoff while
omitting drawing. It is not a full-render throughput or visual test.

Every run matches the real-speed period4 lifecycle reference across 1,595
conservatively completed hashes, ten sound requests and all six authoritative
field-1457 regions. Each output directory retains its measured histogram and
comparison. Together with the prior long/varying tests, this verifies the road
candidate's simulation invariance across the requested short scheduling cases;
it does not close its B handling, hardware performance, or remaining transition
gates. No production source or default runtime behaviour changes in this check.

### Road diagnostic arithmetic cost

The player's reference arithmetic now replaces signed multiplication by 768
followed by an eight-bit arithmetic shift with three times the sign-extended
low word. Signed quarter division uses a negative-input bias of three before
an arithmetic shift, then subtracts four times the quotient to retain the
signed remainder. Exhaustive comparison of all 65,536 signed-word inputs with
seven possible carries (-3 through +3), 458,752 combinations, matches the
preceding expressions exactly.

The unpadded change shortened the helper and shifted later code. Direct normal
candidate measurements therefore included two layout controls:

| Candidate | Cached 020 fps | NoCache 020 fps | 060 fps | NoCache distance |
| --- | ---: | ---: | ---: | ---: |
| Preceding lifecycle | 11.9 | 6.7 | 21.5 | 3,311,794 |
| Shortened arithmetic | 11.8 | 6.7 | 21.8 | 3,321,603 |
| 12-byte pad, selected | 11.9 | 6.7 | 21.7 | 3,321,603 |
| 10-byte exact-address control | 11.9 | 6.7 | 21.8 | 3,292,128 |

These are `c-road-lifecycle-cost`, `c-road-arithmetic-cost`,
`c-road-arithmetic-pad-cost` and `c-road-arithmetic-pad10-cost`. The selected
padding follows an unconditional jump and is not executed. It restores the
later movement/AI code-copy locations; the immediate actor helper starts two
bytes later than before. The exact-address control restores that helper too,
but worsens the live-field NoCache sample. None closes the distance gate.
The selected layout gives a small measured 060 improvement without the
unpadded cached-020 regression; this is not a broad performance acceptance.

`c-road-arithmetic-final` matches the preceding varying-cadence lifecycle run
across 1,595 completed hashes, ten sound requests and all six field-1457
regions. The measured enabled normal candidate is 19,076 bytes, SHA-256
`f168ec601a55a63d127fdb220979641582e3d3e1c45009c38124297ee03a1cb8`.
The tracked correction remains opt-in diagnostic code; the default normal
binary still matches SHA-256 `4a6a5d667acaf0462ead705b5a342e5f6de8449e2fbe3dedb7bef638b82a966f`.

### Current road diagnostic: MMU and wreck-fixture checks

`c-road-final-mmu` passes the 040 and 060 functional MMU cells using the current
arithmetic and lifecycle code (`C_SIMULATION`, `VERIFY_MMU` and
`VERIFY_C_ROAD_TIMING`). Both report TC `$8000`, CACR `$80008000`, exclusively
one-field simulation deltas, and distance 3,331,396. The tested 19,712-byte
instrumented binary SHA-256 is
`83c13f85e4ab6fa9329fecffe37b17500ec981e0d31211b49b7c030e819af6d5`.
These are translation/functionality checks with the harness's data-cache
emulation disabled, not physical cached throughput measurements.

The retained old wreck tape now produces arrest under the corrected physics:
`c-road-final-wreck-fixed` exits at field 7963 after 7,962 completed ticks and
18 sound requests, with damage 9. Its final screenshot shows BUSTED; restart
and the road-state zero checks pass. It must not count as wreck coverage.

A controlled wreck fixture uses the previously recorded lane-following finish
route, with starting damage set to 10 by a private diagnostic reset patch.
Only that starting condition changes; subsequent collisions accumulate damage
through the native game code. The exact fixture patch is retained in
`c-road-wreck-fixture-fixed-build/fixture.patch`. It is absent from tracked
source and normal builds. This is explicitly a controlled transition test,
not a claim that the old unmodified wreck tape still has the same outcome.

`c-road-wreck-fixture-fixed` and `c-road-wreck-fixture-vary` match all 14,443
completed hashes, 57 sound requests, terminal timing and the six authoritative
terminal regions. Both captured damage 32 and exit field 14444, without a
finish. The fixed run's inspected screenshot shows WRECKED. Both restart with
all twelve player road-state bytes and 140 per-actor carry bytes zero.
Together with the unseeded finish and arrest replays, this covers the three
native exit types for the road-state transition audit, with the stated wreck
initial-condition limitation. B-equivalence and remaining performance/control/
latency checks are still open; the correction remains diagnostic-only.

## Preceding runtime: Fast RAM movement and collision code

Normal and lean runtime builds now select `C_PHYSICS_FAST`; full diagnostics
opt in with `VERIFY_C_PHYSICS_FAST`. The 7,040-byte copy and its eight entry
redirects are initialized after the existing C patches, only when the
Enhanced framerate/CPU/Fast selection succeeds. Actors, graphics, simulation
quantum and the native display handshake are unchanged. The implementation
and relocation details are described in the candidate audit below.

The normal slave is 15,600 bytes, SHA-256
`63fbc6383922e5ce96d05d90e08445135ae5e978409877b7302d685cde4641c8`.
The tracked-source normal and lean builds are byte-identical to
`c-physics-fast-runtime-build`; its full diagnostic is byte-identical to
`c-physics-fast-full-build`. These identities connect the candidate tests to
the integrated implementation.

`c-physics-fast-runtime-matrix` passes all 11 normal configurations:

| Configuration | Prior fps | Current fps |
| --- | ---: | ---: |
| A500 | 8.5 | 8.5 |
| Chip-only 020 | 12.5 | 12.5 |
| Fast 020, default | 10.0 | 10.3 |
| Fast 020, Cache | 10.0 | 10.2 |
| Fast 020, NoCache | 5.0 | 6.3 |
| 030, default/Cache | 12.5 | 16.6 |
| 040, default/Cache | 16.6 | 18.8 |
| 060, default/Cache | 18.5 | 20.7 |

A500 and Chip-only 020 initial, field-590 and final state hashes exactly match
the preceding runtime, which matched B. Both MMU functional cells pass in
`c-physics-fast-runtime-mmu`, with TC translation enabled and CACR
`$80008000`. These are functional checks, not real 040/060 data-cache timings.
`c-physics-fast-runtime-off` verifies all eight new entry sites plus the
previously checked enhancement hooks retain their native instructions.

Full finish/arrest/wreck comparisons in `c-physics-fast-{finish,arrest,wreck}`
match 12,822/8,377/11,945 completed hashes and 24/241/120 sound requests.
All six authoritative terminal regions and terminal times match their
respective steering references; each next race resets to `[99,98,0,1]`.
The varying-cadence attack replay remains the 1,596-hash comparison below.

Normal keyboard and CD32 tests pass in `c-physics-runtime-{input,pad}`:
release recentres steering, pause holds field 161, and resume advances active
time. Observed stack use is 276/332 bytes with guards intact. Demo fire exits
at field 507; timeout exits at 3,598 with the existing two-field timer offset.
Both reach a normal race at field 100. Screenshots were inspected; demo stack
use is 268/284 bytes with intact guards.

`c-physics-fast-runtime-visible` measures 180/160/140/220/200/180/160/240 ms
over phases 300–307: median 180 ms versus the preceding runtime's 170 ms
and B's 200 ms. Seven phases are one capture field later than the preceding
runtime, while phase 302 is four fields earlier. These capture-end estimates
have one-field resolution; neither aggregate throughput nor median response
proves response equivalence at every phase. This trade-off remains explicit.

Three live-field A4 distances still exceed B's 1% tolerance: default Fast 020
(-1.953%), Fast 020 Cache (-1.471%), and Fast 020 NoCache (-1.663%).
All 030/040/060 cells are within that distance tolerance, but this does not
settle handling/rank/crash equivalence. Accelerated throughput still falls
short of B in several configurations. C remains incomplete.

## Preceding runtime: measured rider-heading prediction

Normal and ordinary lean runtime builds now select `C_POSE_PREDICT` with
`POSE_PREDICT_MEASURED`. Explicit `VERIFY_C_POSE_PREDICT` selection preserves
fixed-horizon diagnostic controls. That normal slave is 8,212 bytes,
SHA-256 `91ba5e9a2c5828c0cd7031bf68ff0917e6c0f62c928b3475ef266fd0bc79e484`.
Prediction remains behind the existing Enhanced framerate/CPU/Fast selection.
It affects the displayed rider heading, never authoritative actors or events.

`c-pose-predict-runtime-visible` measures all eight input phases on this normal
binary: 160/140/220/200/180/160/140/220 ms, median 170 ms, versus the preceding
runtime's 230 ms and B's 200 ms. Phases 302 and 303 still trail B by 20 ms;
the aggregate gain does not establish response equivalence at every phase.

`c-pose-predict-runtime-matrix` passes all 11 normal configurations with the
same fps as the preceding automatic-cache runtime below. A500 and Chip-only
A1200 initial, field-590 and final state hashes exactly match B.
Both integrated MMU checks pass in `c-pose-predict-runtime-mmu`.
The expanded `c-pose-predict-runtime-off` probe verifies original instructions
at the three new prediction hook sites as well as all previously checked
enhanced hooks when CUSTOM2=0.

Normal keyboard and CD32 steering/release/pause checks pass; active time
holds at field 161 while paused. Stack guards are intact, with 276/368 bytes
observed respectively. Both demo exits pass: fire at field 566 and timeout
at 3,598 with the native timer offset, then a normal race at field 100.
The resulting race screenshots were inspected. Demo stack use is 228/232
bytes with guards intact.

The rebuilt full diagnostic in `c-pose-predict-integrated-full-build` is
byte-identical to `c-pose-predict-measured-finish-build`. In addition to the
successful finish below, `c-pose-predict-measured-arrest` matches all 8,377
actor hashes and 241 sound requests against `c-steering-finish-drive`, exiting
at 8,378. `c-pose-predict-measured-wreck` matches all 11,945 hashes and 120
requests against `c-steering-quarter-fullrace`, exiting at 11,946. Both
match terminal authoritative ranges and restart with capture `[99,98,0,1]`.
These diagnostic replay checks complement the actual normal-build tests.

The current live-field A4 matrix still has four distances outside B's 1%
tolerance: default Fast 020 (-1.373%), Fast 020 NoCache (-1.953%), and both
060 configurations (-1.105%). Frame rates remain below B on accelerated
hardware, and handling equivalence remains unresolved. Prediction does not
close those gates; C is still in progress.

### Unit-timestep arithmetic experiment: no measured throughput gain

`c-unit-delta-{build,cost}` specializes five direct timestep multiplies at
`$8b756`, `$8b764`, `$8b8f0`, `$8d536` and `$8e0d6`, plus the collision
division at `$8ef64..$8ef6b`. For delta one, signed multiply becomes sign
extension and unsigned multiply becomes zero extension. The collision
dividend is explicitly sign-extended from a word, so division cannot overflow;
zero extension followed by `TST.W` preserves the quotient, zero remainder and
word-sign flags needed by the following `BPL`.

The expanded `c-unit-delta-v2-*` candidate also specializes acceleration at
`$8b4b8`/`$8bd1c` and speed-to-displacement at `$8b4d2`. It preserves D2's
upper word and unit low word as well as the arithmetic result and flags.
The native disassembly has no direct branch into the replaced sequence
interiors. Both experiments require one-field simulation and use the existing
enhanced-path gate.

Each candidate has an equal-size, equal-layout control patch list that writes
the original native instructions. On the cached 020, the initial candidate
and control both render 193 frames over fields 100..1,000 (10.722 fps).
The expanded candidate and its control both render 192 (10.667 fps).
The different layouts between experiments mean the one-frame difference is
not evidence that the arithmetic changes made rendering slower; within each
controlled comparison there is no measured frame-count gain.

Both `c-unit-delta-replay` and `c-unit-delta-v2-replay` match all 1,596 completed
actor hashes, three sound requests, and the six authoritative field-1,457
regions against `c-audit-period-4`, with the varying render-interval pattern.
This establishes the observed replay equivalence, not a throughput benefit.
The expanded patch is retained privately in
`tmp/dev/tmp/c-unit-delta-v2-build/source.patch`; no specialization remains in
the tracked runtime. Normal runtime identity and the remaining C gates are
unchanged. Further optimization needs to target larger costs than these
isolated timestep arithmetic operations.

### Actor-memory audit: race state shares storage with graphics

`c-actor-memory-audit` examines the current 8,212-byte normal runtime without
changing its memory or instructions. During a 300..320 live-field capture,
19 complete recorded fields contain 44,893 bus accesses into
`$a5d60..$a6edf`, all classified as CPU accesses. They touch 417 distinct bus
addresses and account for 10.779% of the sample's 416,482 CPU bus records.
This identifies a substantial source of Chip RAM traffic, not a measured
speedup or proof that the region is CPU-only throughout the game.

The native snapshot has 202 instruction operands referring into this address
range and 51 populated pointer slots. These are address references, not all
semantically actor references. Three real operands require decoding from the
correct entry rather than following the linear disassembly through preceding
data: `$898e6` (instruction at `$898e4`), `$8af7c` (`$8af7a`), and `$8b48a`
(`$8b486`). A blind word-aligned scan finds another 40 address-shaped values
that straddle instructions and must not be relocated.

The live runtime matches 201 of those native operand values. The exception
is `$8a8e8`, whose original player comparison is covered by the integrated
prediction hook. The replacement comparison lives in the slave. Its emitted
listing contains 12 direct references into this range; they also need explicit
handling. The existing Fast RAM object-projection copy has no direct operand
in this range. Populated data pointers include `$9017c`, the lists around
`$90948`/`$909cc`, and the actor tables at `$94192..$94226`; the sampled slots
are not an exhaustive lifetime inventory of every possible pointer.

Crucially, the same Chip addresses serve graphics routines outside the actor
lifetime. `$8172c` copies a variable-sized resource to `$a5de0`, then `$afd9c`
turns its relative image offsets into absolute pointers. `$81fb2` reads the
first such pointer from `$a5de2` into A1 and can call `$b452a`; that path writes
A1 to `BLTAPT` at `$b465a`. `$83ba4` and `$b2b4c` also use `$a5de0` as a
resource-load destination. `$b2b58` copies 6,048 bytes from there to `$f0de`,
extending beyond the 4,480-byte actor region. Globally rebasing every reference
would therefore both risk feeding Fast RAM to DMA and exceed a small
actor-only allocation.

Any actor relocation must split these lifetimes: keep graphics scratch and
DMA sources in Chip RAM, establish separate Fast actor storage for races,
and audit initialization, results, exit and restart transfers. It must rebase
typed actor references and the slave's helpers, not every matching literal.
The audit JSON and retained bus trace document the observations. No relocation
is installed yet; this is a concrete D3 dependency for pursuing C's remaining
simulation cost, not completion of D3's eligibility or transition audit.

### Race-only Fast actor experiment: less physics traffic, inconsistent fps

A private source generated by `tmp/dev/tools/make_actor_fast_source_c.py`
tests the race lifetime only. After field 100 it copies all 35 128-byte actors
to a guarded optional Fast allocation, rebases 167 native race operands and
12 emitted slave operands, and updates the race pointer tables. Graphics
scratch references remain in Chip RAM. Initialization preflights the native
operands and flushes caches after patching. Exit/restart restoration is not
implemented, so this is not a candidate for normal-runtime integration.

The equal-layout control performs the same allocation, copy, preflight and
patching work with a zero relocation delta, leaving active actors in Chip RAM.
The two 10,572-byte diagnostic binaries differ by five bytes within one
six-byte instruction span. The candidate SHA-256 is
`10c33ba16e147fe39e5f5fbe519a99c64b74e1aaa04de237409a39bc8ce2da39`;
the control is
`a20667b5bc6c4b238cebef86ab3595e54a6dee6c14e4ccc35a9d6a09223b3403`.

Cycle-exact 020 measurements subtract each run's initial frame count:

| Input/window | Cache policy | Chip actors | Fast actors |
| --- | --- | ---: | ---: |
| UP at 100, fields 100–1000 | Cache | 193 | 174 |
| UP at 100, fields 100–1000 | NoCache | 108 | 113 |
| UP at 200, fields 200–1100 | Cache | 216 | 218 |
| UP at 200, fields 200–1100 | NoCache | 144 | 148 |

Each window is 18 seconds. Delaying UP changes the scene as other riders
continue moving; compare within each row, not between the two start times.
The original cached scenario also regresses after initialization: fields
300–1000 produce 153 control frames versus 140 candidate frames. Allocation
guards pass throughout. The `c-actor-fast-replay` comparison against
`c-actor-fast-control-replay` matches all actor, clock, camera and rank hashes
at 501 completed ticks, 100 through 600. This establishes short-race equivalence,
not attack/crash, full-race or transition coverage. Positions sampled at
arbitrary live fields are not equal-tick comparisons.

The cached profiles `c-actor-fast-profile` and `c-actor-fast-control-profile`
cover fields 300–800 after UP at 100. The candidate produces 90 frames versus
103. Physics at `$8b486..$8eff7` falls from 5,426,800,256 to 5,027,184,640
profile units (7.4%) and from 3,984,370 to 3,081,461 Chip accesses (22.7%).
However, the native vsync poll at `$aecf0..$aecf5` rises from 1,274,019,584
to 2,350,782,080 units. Its additional waiting exceeds the measured physics
saving; the sampled blitter waits also cost more. These observations do not
establish the cause of the changed phase or justify removing the native
display handshake.

The prototype and its harness remain under ignored `tmp/dev/`. There is no
reliable overall throughput benefit to promote, and the normal runtime is
unchanged. One scheduling question remains worth isolating: `step_main`
currently rereads the live field clock on every catch-up iteration. A private
comparison could capture the target once per outer frame, preserving every
elapsed tick for subsequent frames, to test whether chasing newly arriving
ticks contributes to the phase sensitivity. That hypothesis is untested;
it must not introduce a limiter, discard time or weaken latency gates.

### Fixed frame-target scheduling experiment: rejected

The subsequent private `c-frame-target-source` captures the live field counter
once on entry to `step_main`, then consumes ticks through that target. Fields
arriving during catch-up remain due on the next outer frame; the prototype
neither discards elapsed time nor adds a wait. Its equal-layout control retains
the same capture but compares against the live clock on each iteration.
The experiment starts from the normal source, without actor relocation.

`c-frame-target-cost` and `c-frame-target-control-cost` run the cycle-exact
cached 020 with CUSTOM2=1 and UP at field 100. Both start with 29 rendered
frames. Over fields 100–1000, the fixed target produces 183 frames versus
193 for the live-clock control. Sampled simulation cursors at fields
100/300/600/1000 are 97/297/596/998 versus 99/299/599/999. These samples
show greater simulation age in the candidate, not dropped ticks or a measured
input-response result. The result supplies no reason to replace the current
catch-up loop. No full gameplay or latency acceptance is claimed.

Both diagnostic binaries are 8,844 bytes. Candidate SHA-256:
`d5a7a209f85fb89f6175c17f3121d467a62ea244ee5a4ed6d1513c53997224b1`;
control:
`9de194737abed1dd117e0ee009c07e6f2924e9ef5f9d8375f3ab71c77188b2ee`.
The exact source delta is retained in
`tmp/dev/tmp/c-frame-target-build/source.patch`. Normal runtime code remains
unchanged. This rejects this particular scheduling change; it does not explain
the actor-relocation regression or close C's outstanding throughput gates.

### Actor relocation handoff trace: different deadline phases

`c-actor-fast-handoff` and `c-actor-control-handoff` use the same tested actor
binaries as above, cached cycle-exact 020, UP at field 100. Each collects
400 breakpoint events beginning at field 300: render entry `$875c8`, swap
entry `$87736`, swap return `$8773c`, publication `$871dc`, and consumer
release `$8713a`. The breakpoints observe existing instructions; no timing
instrumentation is inserted into the slave. The retained JSON includes
beam position, live field, SOFT counter, record readiness and buffer pointers.

Comparing the common live-field window 310–700:

| Observation | Chip actor control | Fast actors |
| --- | ---: | ---: |
| Render entries | 77 | 66 |
| Median render-entry beam line | 115 | 227.5 |
| Median swap-entry beam line | 146 | 268 |
| Swap entries before line 250 | 76 of 78 | 24 of 65 |
| Complete swap intervals of five fields | 72 | 3 |
| Complete swap intervals of six fields | 4 | 62 |
| Median swap-return beam line | 254 | 254 |

Counts differ because the window cuts through different frames; interval counts
use consecutive returns wholly inside it. Beam medians describe phase within
the raster, not elapsed duration across a wrapped raster.

Both record-ready flags are zero at every sampled render entry, and screen
buffers remain distinct and alternate at consecutive swaps. The slower cadence
therefore does not arise from waiting for an occupied producer record at that
point. Fast actors usually finish drawing after the line-250 SOFT signal and
wait for the next one. This supports the earlier flat profile's increased
vsync wait, while preserving the requirement for a safe buffer handoff.

The trace establishes where the deadline is missed, not why the initial
timing differs or how much individual drawing/simulation operations contribute.
Extra waiting also means more elapsed ticks to consume before the next render,
which can sustain a slower cadence; that feedback is an interpretation, not an
isolated causal measurement. Do not remove the original swap wait or infer a
fixed frame limiter from these five/six-field intervals. The next optimization
needs enough measured work reduction to improve complete frame throughput,
with phase and input-response checks alongside instruction/Chip-access counts.

### Broad movement/collision code copy: promising private candidate

The next experiment copies `$8b486..$8d005` (7,040 bytes) into the selected
slave's Fast RAM hunk after installing the existing C hooks. Actors, lookup
tables and graphics stay at their native addresses. Decoding the three code
spans `$8b486..$8c583`, `$8c5a8..$8ce7f`, and `$8cef0..$8d005` covers
1,922 instructions with no PC-relative data operands. Embedded data between
those spans is copied but its absolute native references are not rebased.
Seventeen word-sized branches leaving the copy use nearby absolute-JMP stubs.
Internal relative branches keep their offsets; absolute and indirect calls
retain their native destinations. Eight native entries redirect into the copy:
`$8b486`, `$8baec`, `$8bbe6`, `$8c130`, `$8c48e`, `$8c5a8`, `$8c8ae`, `$8cef0`.
Existing steering wrappers retain their canonical native return addresses.

The private generator is `tmp/dev/tools/make_physics_fast_source_c.py`.
`c-physics-fast-probe` checks all 7,040 copied bytes, accounting for the 17
branch fixups and eight overwritten entry points, and verifies each stub's
destination. The observed copy begins at `$9fa4f0`. The equal-layout control
allocates/copies/fixes the same block but skips installing entry redirects.

Cycle-exact 020, UP at field 100, fields 100–1000:

| Cache policy | Control frames | Candidate frames | Control fps | Candidate fps |
| --- | ---: | ---: | ---: | ---: |
| Cache | 192 | 198 | 10.667 | 11.000 |
| NoCache | 108 | 128 | 6.000 | 7.111 |

These subtract each run's own initial count: cached control/candidate 29/28,
uncached 18/19. They establish gains in these scenarios, not yet a general
hardware or phase-independent improvement. Results reside in
`c-physics-fast[-control][-nocache]-cost`. Both cost binaries are 16,200 bytes:
candidate SHA-256
`493d15b2826fb79e4a05b8f52d6d2aed78e08e639e78ed8f9c1065d345049503`,
control `e576dfb9f06f5c68d4b14722ed1caeff6792b151a33a95808973256ecdcffa87`.

`c-physics-fast-varying` uses the seeded attack tape and varying render
intervals, including 12 and 16 fields. It matches `c-audit-period-4` across
1,596 completed actor hashes, all three sound requests, and the six
authoritative field-1,457 regions (actors, clock, camera and ranks). Raw
snapshot equality is not claimed for presentation-owned bytes.
The 44,716-byte full diagnostic uses long-distance initialization addressing
because its snapshot/hash storage exceeds short PC-relative reach; its SHA-256
is `adb83105950f18443f920fc63e900fe97c0810cfc19338f832aa0a2006d429da`.
Both tested source deltas are retained in their build directories.

This candidate remains private and normal runtime code is unchanged. Before
promotion it needs full finish/wreck/arrest and restart coverage, the normal
hardware/disabled-toggle matrix, visible-response phases, and the existing
distance/handling checks. The modest cached gain does not by itself close C's
throughput deficit against B.

### Combined AI/acceleration helper copy: next private candidate

`c-physics-integrated-profile` profiles the integrated lean runtime over fields
300–800 on the cached cycle-exact 020, after UP at 100. It renders 108 frames.
The relocated movement/collision code and its stubs consume 1,943,214,848
profile units; the remaining native `$8b486..$8eff7` range consumes
2,378,648,832. These must be added when comparing simulation cost after
relocation; looking only at the native address range would omit executed work.
The leading remaining native ranges include AI dispatch `$8d2c0..$8d409`
(375,215,872 units), acceleration `$8dd66..$8de6b` (299,334,528), and
`$8e166..$8e251` (252,138,496). Range totals are flat-PC observations,
not inclusive function costs.

The next private copy groups four spans: `$8d2c0..$8d8cf`,
`$8dd66..$8de6b`, `$8e166..$8e2d5`, and `$8da5c..$8db09`.
Together they occupy 2,356 bytes with no PC-relative data operands.
Thirty relative branches need adjustment: transfers between copied spans
go directly to the matching copied target, while remaining external targets
use nine native JMP stubs. Eight entry redirects cover the four AI entries
and the four helper entries. Two stubs in the existing movement/collision
copy now jump directly to the copied helpers, avoiding a native trampoline.
Native data and mutable PC-relative tables outside these spans stay in place.

`c-physics-aux-probe` verifies every copied byte after accounting for fixups,
all entry redirects, cross-copy targets, native stubs and fallthrough jumps.
The equal-layout control performs the same copies/fixups but skips installing
entry redirects and retains the two existing native helper destinations.
This combined experiment differs from the previously rejected isolated AI
copy: several hot callees now execute in Fast RAM too.

Cached cycle-exact 020 cost runs `c-physics-aux-cost` and
`c-physics-aux-control-cost` produce 219 versus 195 frames over fields
100–1000 (12.167 versus 10.833 fps), subtracting initial counts 30 and 28.
The paired `-nocache-cost` runs produce 138 versus 128 frames
(7.667 versus 7.111 fps), both starting at 19. This is a measured benefit
in two scenarios, not yet a hardware-wide performance result.

Both lean diagnostics are 19,208 bytes. Candidate SHA-256:
`b3eaf5b07ce6fd23c3fab3bfdcb24d81d118dc5d2fe2aed98a5de3c5bb5cb742`;
control:
`604aeaa0f3c2c04dbfcdc848fef26eac5e8df2b346bea45e96a5b2fb75ed384d`.
`c-physics-aux-varying` matches `c-audit-period-4` across 1,596 completed
actor hashes, all three sound requests and all six authoritative field-1,457
regions. Its full diagnostic is 47,708 bytes, SHA-256
`57109b5768be7369b16c3e0d96dda9444088fe4746a58d1ced801bc1014641e0`.

The generator `tmp/dev/tools/make_physics_aux_source_c.py`, manifest and exact
`c-physics-aux-build/source.patch` preserve the experiment. It is not enabled
in the normal runtime. Full finish/arrest/wreck and restart replay, normal
hardware/MMU/disabled checks, controls/transitions and response phases remain
required before integration. The normal binary remains the integrated
15,600-byte movement/collision version documented above.

## Preceding runtime: automatic enhanced-path caching

Normal and lean runtime builds now select `C_CACHE`; full diagnostics retain
`VERIFY_C_CACHE` as an explicit alias for reproducible references. SetCPU runs
only after the existing master-toggle/CPU/Fast selection succeeds. It uses
the policy validated below and honors WHDLoad `NoCache`.
The normal slave is now 7,940 bytes, SHA-256
`b881288139d4b54192648e9533139ce7ace28a8de21daf1e7cdadca34ebed2ee`.
The earlier 7,920-byte audit and experiments below retain their historical
binary identities rather than silently becoming evidence for this build.

`c-cache-runtime-matrix` passes all 11 normal configurations:

| Configuration | Standard-window fps |
|---|---:|
| A500 1 MB Chip | 8.5 |
| A1200 Chip only | 12.5 |
| A1200 Fast, plain or `Cache` | 10.0 |
| A1200 Fast + `NoCache` | 5.0 |
| 030/50, plain or `Cache` | 12.5 |
| 040/25, plain or `Cache` | 16.6 |
| 060/50, plain or `Cache` | 18.5 |

Default Fast-RAM 020 and 030 improve from 5.0/7.5 to 10.0/12.5 fps.
Already-cached rates do not improve. A500 and Chip-only A1200 exactly match
B's initial, field-590 and final state hashes. `c-cache-runtime-off` retains
the original instructions at every enhanced hook inspected by the dispatch
probe. Both integrated MMU configurations pass in `c-cache-runtime-mmu`.

The rebuilt integrated MMU diagnostic is byte-identical to
`c-cache-policy-pages-build`, and the rebuilt full-finish diagnostic is
byte-identical to `c-cache-finish-build`. Thus the preceding page-descriptor
and 12,822-hash finish/restart checks apply to those exact diagnostic
instructions. They supplement the separate actual-normal matrix above.
Normal keyboard and CD32 pause/release tests pass without a user `Cache`
option; active time holds at field 161 while paused. Stack guards remain
intact, with observed use of 256 and 344 bytes.

This removes the need for a separate cache option on the selected enhanced
path. It does not make the cached runtime faster than B, remove the A4
distance/handling differences, or close the remaining response regression.
C remains in progress.

### Current normal-build response and rider-pose threshold

`c-cache-runtime-visible` repeats all eight input phases (fields 300..307)
against paired neutral runs using the actual 7,940-byte normal binary above.
Upper estimates are 260/240/220/200/180/260/240/220 ms (median 230 ms).
The B reference `b-visible-phases` is 180/220/200/180/220/200/180/220 ms
(median 200 ms). Screenshot capture has one-field timing uncertainty; these
are visible-pixel response measurements, not input sampling latency.
Automatic cache integration has not removed the response regression.

Native debugger probes `response_timeline_c.py` and `response_pose_c.py`
in the ignored harness record the actual normal binaries without installing
instrumentation. Evidence is in `{b,c}-current-response-{timeline,pose}`.
The pose probe adds `$8a92c`, filters to the player actor, and records the
selected sprite index in d0. Both binaries read heading thresholds 4/13/32
from `$a7bfa`. For RIGHT injected at field 300:

| Path | Render start | Player heading | Pose index | Swap return | First changed capture |
|---|---:|---:|---:|---:|---:|
| B | 302 | 1 | 3 | 305 | unchanged |
| B | 305 | 4 | 2 | 308 | 309 |
| C | 304 | 3 | 3 | 307 | unchanged |
| C | 309 | 11 | 2 | 312 | 313 |

C first selects pose 2 during catch-up at live field 307, simulation cursor
305, heading 5. That selection cannot appear in the frame already rendered
from cursor 304. The first changed B difference image contains only the
rider; C's includes rider and scenery. Both images were inspected.
Native `$aec78` exchanges `$404`/`$408` and publishes the new `$404` through
the copper pointer writer `$aec2c`; the observed delay does not establish an
extra queued frame or tearing.

This narrows the first-response problem to a discrete sprite threshold and
the time between rendered frames. It does not justify changing authoritative
steering to hit the threshold earlier. A next experiment can predict the
presentation heading through the render interval, with no added wait and
without changing actor state, collision inputs, or simulation pose events.
It must still pass phase-swept visible response, release/reversal behavior,
and authoritative replay checks. No prediction is enabled by this audit;
the throughput, A4, and response gates remain open.

### Diagnostic presentation-heading prediction

`VERIFY_C_POSE_PREDICT` adds a presentation-only experiment behind the existing
enhanced-path selection and CUSTOM2 conditional patch list. It retains the
last four authoritative player headings, estimates three fields of further
heading change, and supplies that estimate only to the player's ordinary
rider-sprite selector at `$8a8e2`. It never stores prediction in the actor.
The simulation-owned pose/event pass always receives the authoritative
heading. `POSE_PREDICT_FIELDS=0` builds a control with identical code layout.
The experiment requires one-field simulation and is not selected by normal
or ordinary lean runtime builds.

Prediction requires held steering in the same direction as the observed
heading change. Release, opposed heading, and reversal through zero suppress
it. The zero-heading guard matters because native code has already chosen
the sprite mirror bit before this hook; predicting negative heading from
zero would otherwise use the wrong orientation. Crash/attack sprite branches
that bypass this ordinary pose selector are unaffected.

The initial cached-020 eight-phase run, `c-pose-heading-predict-visible`,
measures 160/140/220/200/180/160/140/220 ms, median 170 ms.
`c-pose-heading-control-visible` measures
260/240/220/200/180/260/240/220 ms, median 230 ms. Those diagnostic binaries
differ in one immediate byte (prediction horizon 3 versus 0).
The first changed image at phase 300 contains only the rider, as intended.
This improves the aggregate response measure, but phases 302 and 303 remain
20 ms behind B. It is not proof that every input phase now matches B.

The corrected mirror-guard build is `c-pose-heading-predict-v2-build`:
8,740-byte diagnostic SHA-256
`d686121d8a98a95d69817bb96a5ab4a3c33f5413a0232e4f610890dfcd681273`.
Its complete repeat in `c-pose-heading-predict-v2-visible` reproduces all eight
response measurements above, including the 170 ms median.
`c-pose-heading-predict-v2-release` probes 60 player pose calls through release
at live field 311 and opposite input at 321. Simulation calls remain exact;
render headings 11 and 7 remain unpredicted after release, zero remains zero
on reversal, and negative prediction resumes only after heading becomes
negative. This checks the values entering sprite selection, not just input
flags.

`c-pose-heading-predict-v2-replay` matches `c-audit-period-4` on all 1,596
completed actor hashes, all three sound requests and the six authoritative
snapshot regions listed above at field 1,457. Stack guards remain intact
(228 bytes observed). This is a four-field rendered-cadence replay, not yet
full cadence, full-race, or hardware coverage for prediction.

`c-pose-heading-{predict,control}-v2-cost` both render 192 frames between
fields 100 and 1,000 (10.667 fps), with identical recorded cursors and player
positions. The two binaries differ only in the horizon immediate byte.
This isolates prediction versus zero prediction in this straight-line
diagnostic; it does not establish zero overhead versus the uninstrumented
normal runtime.

Normal binaries remain byte-identical to the current 7,940-byte runtime.
The diagnostic's fixed three-field prediction horizon is an experiment for
the measured 020 render interval; it is not a calibrated policy for every
CPU. C's throughput and A4 gates remain open.

### Prediction cadence coverage and measured horizon

The fixed-horizon diagnostic now also passes `c-pose-predict-varying`.
Its observed non-startup intervals include 2/3/4/12/16 fields. All 1,596
completed actor hashes, three sound requests, and six authoritative regions
at simulation field 1,457 match `c-audit-period-4`.
`c-pose-predict-finish` matches `c-cache-finish` across all 12,822 actor hashes,
24 sound requests and terminal authoritative regions: finish at field 12,634,
exit at 12,823, followed by fresh capture `[99,98,0,1]` in the next race.
The finish diagnostics use the established full-snapshot configuration
without the optional Fast RAM stack; the varying replay includes that stack.

`POSE_PREDICT_MEASURED` adds an alternative diagnostic horizon. It observes
the live-field interval from render entry `$875c8` through return from the
native display handoff at `$8773c`, then uses that interval for the next
frame's rider-heading prediction. Race initialization clears the estimate.
It caps extrapolation at four fields after a long frame, with no waiting or
change to the original vsync handshake. This variant rejects simultaneous
whole-view extrapolation or the diagnostic latency hook at assembly time,
since those experiments share patch sites.

Direct player-pose probes in `c-pose-predict-measured-020` and
`c-pose-predict-measured-060` pass simulation isolation and release/reversal
checks. The cached 020 sample uses three fields on all ten observed renders.
The 060 sample uses three fields on five renders and two on eighteen.
Those are measurements of these emulator scenes, not assumed CPU constants
or a claim of cycle-accurate 060 hardware timing.

The measured lean diagnostic is 8,828 bytes, SHA-256
`2c6399c3d25d58f21fb222635498892250d76844455defac1f05ee6b124846ff`.
`c-pose-predict-measured-visible` repeats all eight response phases and
reproduces 160/140/220/200/180/160/140/220 ms, median 170 ms. The remaining
20 ms deficits at phases 302 and 303 against B are unchanged.
`c-pose-predict-measured-bounded` observes horizons 2/3/4 over long-frame
testing and passes the release/reversal and simulation-isolation assertions.

`c-pose-predict-measured-varying` matches the same 1,596 hashes, three sound
requests and six authoritative snapshot regions as the fixed-horizon
experiment; its observed cadence again includes 2/3/4/12/16 fields.
`c-pose-predict-measured-finish` matches all 12,822 hashes, 24 events,
finish/exit fields, terminal regions and fresh-race capture against
`c-cache-finish`. Live checkpoints can land on different in-flight simulation
ticks; these claims use completed-tick hashes and the captured boundaries.

Both prediction variants remain diagnostic-only. All normal binaries built
alongside this work retain the current 7,940-byte runtime hash. These checks
do not yet cover prediction in the normal hardware matrix, demo transitions,
MMU configurations, or the complete arrest/wreck replays, and they do not
close C's existing throughput or A4 differences from B.

## C completion audit against the preceding integrated steering runtime

This audit applies to the normal 7,920-byte runtime with SHA-256
`60ef76f312d7f08ce067b5a6b32966bb47f074ee78fd1166bd1cd1e0a7916bdb`.
Historical tests below retain their original scope; a passing older build is not
automatically a passing test of this binary.

| Requirement | Evidence and remaining work |
|---|---|
| C1a: boundaries and delta consumers | The ownership table and direct-delta audit below identify the race loop, field hook, display handshake and per-frame side effects. |
| C1b: 20 ms simulation, clock, pause and normalized effects | Runtime uses `STEP_FIELDS=1`; camera decay and steering have explicit normalization. Current CD32 pause/resume passes. Original-speed equivalence remains incomplete: live-field distance and collision/handling comparisons still differ from B. |
| C1c: ownership and field input | Simulation owns actor/collision/AI updates, camera, poses and sound requests; display retains buffer publication. Current finish, wreck and arrest tapes compare completed-tick hashes and sound events across cadences. This does not prove B-equivalent handling. |
| C2a: consume elapsed time | Catch-up uses one-field steps and queued field inputs. Terminal ticks stop catch-up; history exhaustion aborts explicitly rather than dropping input/time. Historical overflow and initialization tests exist; current full-race replay validates terminal/restart behavior. |
| C2b: latest state, no delayed interpolation | Normal runtime renders completed simulation state without interpolation. Current normal eight-phase visible-response median is 230 ms versus B's 200 ms. No explicit interpolation delay exists, but the measured response regression remains open. |
| C2c: original safe handoff, no extra pacing | Normal patch list retains the native swap without B's floor/clamp. Historical beam/record trace demonstrates one-field handoff when drawing is omitted. Full-render throughput is not evidence of a limiter; replacing B's safeguards is not fully validated until the other regression requirements pass. |
| C2d: CPU/Fast selection and fallback | Current normal off/Chip-only probes retain original enhanced-hook instructions; current A500 distance and final state match B exactly. The boolean is off by default and gates all runtime enhancements. |
| C3a: explicit cadence replay | Fresh current-model checks below match at observed 1/2/3/4 and varying intervals; one-field cadence requires diagnostic drawing omission. Current finish/arrest and equivalent wreck builds additionally prove full-race varying/longer cadence replay. |
| C3b: A2/A4, controls, demos, transitions and latency | Current normal keyboard/CD32, both demo exits, fallback and latency tests exist, with current-model full-race transition coverage. A4 live-field distance, full opponent order and screenshot review remain unresolved. Equal-duration diagnostic distance accounting does not replace A4's fixed-live-field gate. |
| C3c: hardware throughput and simulation cost | All 11 normal hardware cells now have current-binary results, plus the integrated 040/060 MMU checks. The current normal cached-020 physics profile is refreshed below. Cached throughput is 10.0/12.5/16.6/18.5 fps and remains below B; optimization and its validation remain open. |

C remains incomplete. D–F are expected to provide further rendering speedups;
that expectation does not waive C's original-behavior, latency or verification
requirements. Current-build control/demo and hardware checks are now complete
at their stated scopes. The next work must address the distance/handling,
throughput and response regressions rather than rename the baseline.

### Fresh explicit-cadence replay

`c-audit-period-{1,2,3,4}` rebuilds the current simulation with steering, Fast RAM
object projection and stack, fixed diagnostic RNG, sound-event capture, and
the identical `c-attacks.json` field tape. `c-audit-varying` adds the existing
1/2/3/4/12/2/16/4 interval pattern. All normal binaries produced alongside these
diagnostics match the runtime SHA above.

Observed histograms matter: requested periods 1 and 2 both produce 799
two-field intervals, while periods 3 and 4 produce 533 three-field and 399
four-field intervals. The varying run observes 2/3/4/12/16-field intervals.
These counts exclude startup bins. `c-audit-one-field` uses the existing
`VERIFY_SKIP_RENDER` diagnostic and observes 1,600 one-field intervals. It
retains simulation, geometry and the native display handoff, but omits drawing:
it establishes one-field scheduling coverage, not full-render 50 fps.

All six runs match 1,596 common completed actor hashes and all three sound
requests, including their tick numbers. At completed simulation field 1,457,
the entire actor range `$a5d60..$a6edf`, clock/spawn range `$a5d50..$a5d5f`,
camera longs `$a5d1e/$a5d22`, and rank ranges `$a7220..$a7227` and
`$a59f4..$a59f5` match byte for byte. Thus player distance and actor crash state
also agree at that boundary. All stack guards remain intact.
The full snapshot includes presentation-owned bytes and is not expected to be
identical across cadences.

The linear diagnostic's live step counter can include a tick whose hash has
not yet been written: period 3 stops during tick 1,599. The comparison therefore
uses the shared completed window through tick 1,596, checking every slot is
populated rather than treating the live counter as a publication marker.
The retained `c-audit-varying/comparison.json` records ranges, histograms and
binary hashes. These tests close the explicit short-tape cadence coverage gap;
they do not close the B-reference regressions above.

### Current normal keyboard and demo transitions

`c-audit-keyboard` runs the normal binary on the cached, cycle-exact 020 setup.
Joystick steering reaches 798 at active field 120 and returns to zero after
release at field 160. Keyboard pause holds the active clock at 161 through
the additional paused interval; keyboard resume advances it to 180. The Fast
RAM stack guards remain intact, with 276 bytes of observed use. The slave
copied into the runtime directory matches the audited SHA above.

`c-audit-demo-fire` and `c-audit-demo-timeout` use the same normal binary on the
functional-speed 020 setup. Both show demo position advancing at fields
163/263/363/463. Fire exits the first demo at field 566. The unattended demo
exits at field 3,598, preserving the native 3,600-count timeout with its
initial two-count offset. Both clear the active race hook on exit, then start
a human-controlled race at field 100 with demo mode cleared, lateral position
160 and speed zero. Screenshots were inspected and show the normal race start
after both exits. Stack guards remain intact, with observed use of 216 and
232 bytes respectively.

These checks refresh the previously historical keyboard and demo evidence.
They are functional transition checks, not a new original-behavior distance,
handling or latency result.

### Complete current normal hardware matrix and refreshed profile

`c-audit-matrix-remaining` adds the six missing normal configurations to
`c-steering-runtime-matrix`. All 11 runs use the audited normal-binary SHA.
The table compares actual normal binaries against `b-final-normal-on`, avoiding
instrumentation differences in the older diagnostic matrix.

| Configuration | B fps | C fps | Fixed-live-field distance change |
|---|---:|---:|---:|
| A500 1 MB Chip | 8.5 | 8.5 | 0.000% |
| A1200 Chip only | 12.5 | 12.5 | 0.000% |
| A1200 Fast | 12.5 | 5.0 | -1.373% |
| A1200 Fast + Cache | 16.6 | 10.0 | -1.180% |
| A1200 Fast + NoCache | 12.5 | 5.0 | -1.373% |
| 030/50 | 13.3 | 7.5 | -0.192% |
| 030/50 + Cache | 16.6 | 12.5 | -0.988% |
| 040/25 | 22.6 | 16.6 | -0.836% |
| 040/25 + Cache | 22.6 | 16.6 | -0.836% |
| 060/50 | 23.2 | 18.5 | -1.105% |
| 060/50 + Cache | 23.2 | 18.5 | -1.105% |

Every cell completes the measurement window. A500 and Chip-only A1200 also
match B's initial, field-590 and final state hashes exactly. Five accelerated
cells exceed A4's 1% distance tolerance; none of the accelerated cells improves
on B's throughput. Passing boot/race checks must not be reported as passing
those regression gates. The existing current integrated 040/060 MMU results
remain functional checks with translation enabled, not hardware speed claims.
The retained `comparison.json` records each normal result path and both distances.

`c-audit-runtime-profile` refreshes the actual normal cached-020 flat profile
over active fields 100–600. Native physics/AI addresses `$8b486..$8eff7`
account for 31.165% of recorded units. The largest 256-byte blocks remain
`$8d900` (2.006% of all units), `$8d300` (1.934%), `$8b500` (1.726%),
`$8bc00` (1.617%) and `$8c800` (1.604%). This range excludes relocated slave
helpers and is not the entire inclusive simulation cost. The distribution
still shows substantial work spread across physics and AI; it does not
justify repeating the already rejected AI relocation/invariant-read changes.
Flat emulator units and the 040/060 timing limitations retain the qualifications
documented in the earlier profile sections.

### Distance regression: gear thresholds and road-centre rounding

`b-audit-distance-dynamics` / `c-audit-distance-dynamics` and the extended
`b-audit-road-dynamics` / `c-audit-road-dynamics` trace completed steps on the
cached cycle-exact 020. B uses the preserved seeded reference; C uses the fresh
period-1 diagnostic with current steering, Fast object projection and stack.
Both receive throttle at live field 100. The additional fields are acceleration,
gear, lateral position, height, riding flags, crash state, road centre, road
fraction and displacement. They supplement, rather than replace, the earlier
completed-step distance accounting.

All recorded steps retain lateral position 160 and crash state -1. Every
successive position increment exactly equals the completed speed multiplied
by that step's delta. Thus the earlier endpoint-velocity integration bias is
still present; no additional unexplained displacement term is needed for this
window. Gear thresholds also produce different overshoots: the first shift
completes at speed 5,552 in B and 5,432 in C. This is distinct from lost small
steering movements.

A further difference appears in the road-relative position used for drag:

| First off-road flag | B | C |
|---|---:|---:|
| Completed cursor | 533 | 528 |
| World position | 3,307,451 | 3,216,351 |
| Road centre | -66 | -66 |
| Bike lateral position | 160 | 160 |
| Speed | 10,929 | 10,819 |

C reaches the same road-relative threshold 91,100 world-position units
earlier. Its first subsequent downshift completes at cursor 530, versus B's
545. No steering input or crash explains the discrepancy.

The native calculation at `$8babe..$8bace` combines displacement with `d6`,
the accumulated road-curve change including its fractional lookup difference:
`3 * floor(floor(displacement / 256) * d6 / 256)`, using signed arithmetic
shifts. This is quantized before the result is added to actor `+$36`.
In these traces every nonzero centre update is -3. C has already made 14
such updates at position 2,694,903 (centre -42); B has made only 13 at
2,698,025 (centre -39). Coarser steps can combine curve changes before
rounding, so replacing their delta with one field does not preserve this
stateful effect. For example, a negative product between -256 and -1 rounds
to -1 before multiplication by three.

`c-audit-road-dynamics/comparison.json` retains the first off-road states,
gear transitions and the exact endpoint-integration checks. This initially
identified road-centre integration as a normalization hypothesis. The operand
and fixed-four-field tests below narrow that conclusion: a discrepancy against
one variable-delta B run does not establish an error against the four-field
handling reference. No speed multiplier or road-state correction is installed.

### Road operand trace: distinguish variable B rounding from the reference

`b-audit-road-operands` and `c-audit-road-operands` break at `$8babe`,
before the native road-centre update. They read signed `d6`, displacement and
the old centre, then verify that the next observed centre exactly equals the
previous centre plus the independently calculated update. All 166 B and 503 C
observations pass. The B run contains 160 delta-3 and six delta-4 updates;
all C updates use delta 1.

The C trace has 35 negative curve changes, each -1; B has 34 changes of -1
and one of -2. In the relevant speed range, two small negative changes each
round to a -3 centre update, while one combined change can also round to
only -3. This explains the observed three-unit centre difference without
assuming a different road table or steering input.

An offline four-field grouping of the C operands, tested at all four grouping
phases, still ends at centre -105 and crosses the off-road threshold at
positions 3,216,351–3,248,688. Simply retaining fractional products is not a
faithful correction: it ends at approximately -15.82 rather than -105.
Even multiplying displacement by four before fractional accumulation ends
at approximately -63.94. These are calculations over the captured trajectory,
not closed-loop gameplay tests; they reject a simplistic correction rather
than validate a replacement model.

`b-audit-four-field-road-operands` adds a native B diagnostic with fixed RNG
and `VERIFY_FRAME_PERIOD=4`. Its 126 observed updates all use delta 4 and all
pass the same native-formula check. Its road centre first crosses -64 at
position 3,234,720, compared with C's 3,216,351: the 18,369-unit difference
is smaller than that B step's 43,328-unit displacement. Its -2 curve changes
produce -6 updates at this speed, preserving changes that the mostly delta-3
run combines differently.

This short straight-input trace therefore does not justify altering C's
road-centre integration to match the mostly delta-3 B run. It is consistent
with the four-field reference within its discrete crossing interval; that
is narrower than proving road handling equivalent over a complete course.
`c-audit-road-operands/comparison.json` retains the crossing operands and
delta/curve distributions for all three runs. The original live-field A4
failure remains open, including input retroactivity, endpoint integration,
gear overshoots and rendering debt identified in the earlier accounting.

### Rejected collision-only road projection experiment

The refreshed profile places 4.624% of recorded units in `$89800..$898ff`.
Simulation calls the native road geometry before world-object projection;
rendering calls it again before drawing. The region `$8984e..$8989d`
computes road width and both edge projections. Direct consumers of those
arrays occur in the rendering path, while object collision projection reads
the retained centre, height and occlusion arrays.

The private `VERIFY_C_ROAD_COLLISION` candidate copied the 468-byte native
routine into the already-selected Fast RAM slave hunk. Only simulation used
this copy. A branch skipped the width/edge region, retaining the native render
entry and its complete geometry calculation. It was initialized only after
the master toggle and hardware checks selected C.

`c-road-collision-replay` matches all 1,596 common actor hashes, three sound
requests and the completed-field-1457 authoritative ranges against
`c-audit-varying`. The stack guards remain intact. This is short-tape evidence,
not full-course acceptance or proof that every indirect consumer was audited.

The cached cycle-exact 020 cost comparison over active fields 100–1,000 fails:

| Lean runtime | Completed frames | fps |
|---|---:|---:|
| Current reference | 193 | 10.722 |
| Copied geometry with skip branch | 173 | 9.611 |
| Compact geometry copy | 174 | 9.667 |

The compact variant omits the 80-byte region from the copy entirely and
adjusts the sole loop-back displacement crossing it, from `$ff14` to `$ff64`.
It avoids the extra skip branch but still regresses. No particular cache or
memory mechanism is claimed as the cause without a trace establishing it.
The compact variant was cost-tested only; the full gameplay comparison above
belongs to the first candidate.

Both candidates were removed from tracked source. Their patches, binaries and
measurements remain in `c-road-collision-{cost,compact}-build` and corresponding
run directories; `c-road-collision-reference` is the fresh control.
All accompanying normal builds retain the audited 7,920-byte runtime SHA.
Do not install this reduction merely because it omits arithmetic: neither
measured implementation improves throughput.

### Geometry reduction control: layout alone does not explain the slowdown

`c-road-collision-layout-control-build` differs from the first rejected
geometry candidate in only three binary bytes. Its initializer writes the
original instruction prefix instead of the skip branch, retaining the same
9,044-byte diagnostic layout and simulation-only Fast RAM routine copy.
All native calculations therefore execute in the control.

`c-road-collision-layout-control` produces 192 frames over fields 100–1,000
(10.667 fps), versus 193 for the current-runtime control and 173 for the
skip candidate. This rules out the extra copy/layout alone as a sufficient
explanation for the 20-frame regression.

Same-layout flat profiles over fields 100–600 are retained in
`c-road-profile-{full,skip}`. Full geometry enters rendering 99 times; the
skip candidate enters 83 times. The native next-field polling instruction
at `$aecf0` accounts for 5.839% versus 12.802% of total recorded units,
respectively, with 941,783 versus 2,056,451 executions. At drawing address
`$b17ec`, recorded Chip-access units rise from 3,520,768 over 99 executions
to 108,913,408 over 83; `$b1874` likewise rises from 1,129,728 to 86,915,072.
These measurements show increased waiting, including Chip-access stalls,
despite fewer drawing calls. They do not prove which DMA/arbitration or
frame-phase interaction causes it, nor establish that every removed array
write is irrelevant to every path.

No runtime change is retained. The control patch and binary remain private,
and `c-road-collision-layout-control/comparison.json` records the counts.
Further speed work should examine scheduling and Chip/DMA overlap rather
than infer a benefit from arithmetic counts alone. In particular, the planned
D2 priority audit is relevant; its effect must be measured, not assumed.

### CPU/blitter priority control on the current 020 path

The private `VERIFY_C_CPU_PRIORITY` experiment writes DMACON at enhanced race
preparation/reset, after the existing master-toggle and CPU/Fast selection.
It clears only `BLTPRI` (`$0400`); the equal-layout control sets that bit
(`$8400`). No instruction is inserted in the per-tick loop. The two 8,552-byte
lean diagnostics differ in exactly the set/clear byte at the two writes.
The normal runtime remains unchanged.

`cost_priority_c.py` records live DMACONR and the last completed frame's
DMACONR at fields 100, 300, 600 and 1,000. Every recorded priority bit matches
the requested setting. The lower control bits read `$03f7` with priority
cleared and `$07f7` with it set; live reads can additionally contain blitter
status bits. This verifies the setting in the sampled window, without
claiming to identify the original writer or watch every write.

| Cycle-exact 020 configuration | BLTPRI | Frames, fields 100–1,000 | fps |
|---|---|---:|---:|
| Cache, current reference | set | 193 | 10.722 |
| Cache, equal-layout control | set | 193 | 10.722 |
| Cache, candidate | clear | 183 | 10.167 |
| NoCache, equal-layout control | set | 109 | 6.056 |
| NoCache, candidate | clear | 105 | 5.833 |

The experiment therefore does not improve either tested 020 configuration.
It is not a justification for changing priority on 030/040/060, and does not
complete the all-cell D2 audit. The native setting is retained; the candidate
was removed from source. Evidence is under `c-cpu-priority-*`, including
`c-cpu-priority-clear/comparison.json` and the private patch in
`c-cpu-priority-on-build`. The earlier expectation that clearing priority
would turn Chip stalls into a throughput gain is not supported on current C's
020 path.

### Automatic cache policy candidate

`VERIFY_C_CACHE` now exercises `resload_SetCPU` after C's boolean/CPU/Fast
selection and before installing its game patches. It requests BaseMem
write-through plus instruction/data caches, masking only those settings.
It preserves the existing ExpMem/slave policy and never requests BaseMem
copyback. This remains diagnostic-only; normal builds are unchanged.

The installed WHDLoad autodoc specifies that SetCPU honors `NoCache` without
changing the setup, and flushes caches on return. LoadFile, LoadFileDecrunch
and Patch also document automatic flushing. This avoids adding redundant
flushes to those APIs; native writes/decrunch boundaries still require their
own audit. WHDLoad's cache-handling documentation explains the distinction
between CACR enable bits, MMU page cacheability and hardware Chip/IO cache
inhibition. A CACR reading alone does not prove DMA coherency.

`c-cache-policy-{plain,cache,nocache}` test the same lean candidate on the
cycle-exact 020 with `CUSTOM2=1`. Plain and explicit `Cache` runs produce
identical checkpoints: CACR `$1`, 10.0 fps over fields 100–600 and 10.667
over fields 100–1,000. `NoCache` retains CACR zero, 5.0 and 6.056 fps.
The normal runtime without explicit cache control previously needed the
separate `Cache` option to obtain the faster result.

`c-cache-policy-matrix` tests the candidate without a user cache option:

| Configuration | Race CACR | Standard-window fps |
|---|---:|---:|
| 030/50 | `$2111` | 12.5 |
| 040/25 | `$80008000` | 16.6 |
| 060/50 | `$80008000` | 18.9 |

Both explicit MMU cells in `c-cache-policy-mmu` complete with TC `$8000`
and CACR `$80008000`. These remain functional checks; the emulator configuration
has `cpu_data_cache=false`, so they do not prove physical data-cache coherency
or real 040/060 timing. `c-cache-policy-off` and `c-cache-policy-chip` retain
the original simulation entry and CACR zero when the toggle is disabled or
the hardware selection rejects the accelerated path.

This is a viable candidate for avoiding the default uncached slowdown,
not a resolution of the cached C-versus-B regression. Before normal integration,
verify longer gameplay/transitions with the policy, finish the write/decrunch
coherency audit, and inspect the requested memory policy under MMU translation.
The accompanying normal slave still has the audited SHA; no additional
user-facing cache toggle is introduced.

### Cache candidate: full finish, page descriptors and loader boundaries

`c-cache-finish` replays the existing successful-finish field tape without a
user `Cache` option. Against `c-steering-finish-lane`, it matches all 12,822
published actor hashes, 24 sound requests and terminal actor/clock/camera/rank
ranges. Finish remains field 12,634 and exit field 12,823; the next race
resets the capture to `[99,98,0,1]`. This verifies the cache candidate through
that complete gameplay and restart path, not every championship transition.

The new optional `VERIFY_MMU_POLICY` sidecar captures SRP, URP and both
instruction/data transparent-translation registers on the first race field.
It requires `VERIFY_MMU` and reads these registers only after the existing
040/060 CPU check. It leaves the 320-byte `RRA1STAT` ABI intact; the separate
`RRCMMU01` record follows it. Normal builds contain neither record.

`c-cache-pages-040` and `c-cache-pages-060` walk the captured root/pointer/page
tables for every 4 KiB page of the 1 MB BaseMem area. All 256 supervisor and
256 user descriptors in each run are resident and have cache mode 0
(write-through); none requests copyback. Transparent translations are disabled,
so they do not override those descriptors. The sampled Fast simulation-code
and stack pages have cache mode 1 (copyback), preserving their existing policy.
TC is `$8000`; stack guards remain intact. Descriptor decoding follows the
emulator's 040/060 table-walk implementation, including indirect page descriptors.
Raw registers and every descriptor address/value are retained in `policy.json`.
This proves the requested mappings in these emulator runs, while retaining
the previously stated limit that physical data-cache/DMA coherency is not
emulated by their configuration.

The source/API review accounts for the cache-changing and code-loading paths:

| Boundary | Flush coverage |
|---|---|
| Initial `lomain.ami` loading | `resload_LoadFileDecrunch` flushes on return; automatic enhanced caching has not yet been requested. |
| Boot patch list | `resload_Patch` flushes after installing loader hooks. |
| Intro hooks `$4800` / `$4844` | `PatchIntro1/2` call `resload_Patch`, including the intro reader hook at `$8e58`. |
| Main loader hook `$496a` | `PatchLoader2` applies the main patch list, selects C, calls SetCPU, then applies C patches; each API flushes on return. |
| Disk-reader hooks `$4dca`, `$adf82` and `$8e58` | `ReadSomeFile` delegates to `resload_LoadFile`, which flushes before returning to the loader. |
| Runtime Fast code copies | The object-copy initializer explicitly calls `resload_FlushCache` after writing executable bytes. Diagnostic road-copy initializers do likewise. |

The earlier race trace found mutable data, but no self-modifying instructions,
in the sampled code region. This does not establish an exhaustive write audit
of every unexecuted game path. No redundant flush is added after APIs that
already provide one. These results support proceeding to normal-build
integration and its controls/matrix validation; they do not close C's distance,
handling, cached-throughput or latency regressions.

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

## Fast RAM world-object projection experiment

`VERIFY_C_OBJECT_FAST` copies `$8b02e..$8b37d` (848 bytes) into reserved space
inside the selected C slave hunk. `step_select_path` already proves that hunk
is in Fast RAM; no separate allocation or DMA storage is moved. The instruction
audit covers 263 instructions and 36 relative branches/calls, all targeting
within the copied block. There are no PC-relative data accesses. Absolute data
references continue to address the one authoritative native state.

The C patch list redirects `$8b02e` to the copy. Immediately after applying the
patch list, before native main-game execution resumes, initialization copies the
body and restores the original eight-byte entry instruction in the copy. The
body is copied after patching so other selected patches are retained. A
`resload_FlushCache` follows all writes. Both simulation and rendering calls
through the native entry use the relocated code. Nothing runs this initializer
or installs the entry jump when the master toggle/hardware selection rejects C.

`c-object-fast-copy` confirms the actual entry target `$9fd83c` and byte equality
for all 848 bytes against the patched native body plus its original entry.
`c-object-fast-off` confirms CUSTOM2=0 retains the original entry.
`c-object-fast-040-mmu` and `c-object-fast-060-mmu` reach the race, verify the
copy at `$9fbb20`, and confirm enabled TC translation. These are functional
cache/MMU checks, not cycle-accurate performance measurements.

`c-object-fast-replay` matches all 1,598 common completed hashes, sound events
and the entire tick-1457 snapshot against `c-steering-reference-replay`.
The cached cycle-exact 020 cost window (fields 100–1000) improves from 177 to
193 renders, 9.833 to 10.722 fps, about 9.04%. Initialization and live checkpoint
phases differ, so this frame count is not a claim of equal state at arbitrary
live fields; the completed-step replay supplies that equivalence evidence.
This experiment is independent of deferred width division and remains disabled
in the normal slave, whose SHA-256 remains
`fc07ed239f111fb376dc0101fabffee2dd42bd779190df73c87b1a8cdc16e7cf`.

`c-object-fast-fullvar` matches all 11,945 hashes, 120 sound requests and the
recorded terminal actor/clock/spawn-timer/camera/rank ranges against the unchanged
quarter-steering reference, through wreck at field 11946 and restart. The
Chip-only 020 test `c-object-fast-chip-fallback` retains the original entry even
with CUSTOM2=1. Successful-finish coverage and normal-runtime integration remain
separate outstanding work; this does not close C or the broader D3 audit.

## Integrate Fast RAM projection in the enhanced runtime

`C_OBJECT_FAST` now enables the tested copy/entry patch in normal and lean
runtime builds. Full-snapshot diagnostics retain explicit
`VERIFY_C_OBJECT_FAST` selection so historical references remain reproducible.
The copy is still initialized only after CUSTOM2 and CPU/Fast-memory selection.
Neither the steering candidate nor deferred-width experiment is enabled by this
change. No additional public option is introduced.

The actual normal slave in `c-object-runtime-matrix` measures:

| Cached machine | Previous normal C | Fast projection normal C |
| --- | ---: | ---: |
| 020 | 8.7 fps | 10.0 fps |
| 030/50 | 12.5 fps | 12.5 fps |
| 040/25 | 16.6 fps | 16.6 fps |
| 060/50 | 18.5 fps | 18.9 fps |

These use the existing 500-field cycle-exact window. They remain below B's
throughput and do not establish C completion. `c-object-runtime-off` and
`c-object-runtime-chip` inspect all enhanced hook sites, including the new
projection entry: both retain the original code. The integrated lean runtime's
040/060 MMU probes verify all copied bytes and enabled TC translation; these
functional results are not speed measurements.

The normal slave is now 7,708 bytes, SHA-256
`e7653f3f5964730115faf8a4c0971fb8b984bc46a518c5c1bfb2c8ee3aa6cd89`.
The size increase reserves executable storage within the slave hunk; the
optional expansion-memory stack reservation remains unchanged.

`c-object-runtime-fullvar` uses the integrated projection with the original C
steering and the recorded successful-finish tape, under varying render intervals.
All 14,023 hashes and 52 sound requests match `c-fullrace1`, as do the terminal
actor/clock/spawn-timer/camera/rank ranges, finish field 13835 and exit field
14024. The next race resets capture state to `(93,92,0,1)`. Inspected finish and
next-race screenshots render correctly. This validates successful finish/restart
for this integration, not for the separate revised steering candidate.

`c-object-runtime-pad` tests the actual normal binary: steering/release works,
pause holds active field 161, resume reaches 172, and both stack guards remain
intact (348 bytes observed high-water usage). `c-object-runtime-a500` retains
8.5 fps, distance 3,425,028 and the exact final actor/clock/rank state hash of
`b-final-normal-off`. C still needs further performance improvements and the
remaining handling, latency and A4 acceptance work.

## Road-geometry relocation: no measured cached-020 gain

`VERIFY_C_ROAD_FAST` tests copying only `$8970e..$898e1` (468 bytes) into the
selected Fast RAM slave hunk. The adjacent mutable word at `$898e2` is excluded.
The audit covers 145 instructions and 26 branches, all internal, with absolute
data references and no PC-relative data. Initialization restores the displaced
six-byte LEA, copies the remaining words after the C patches, and flushes caches
before native execution resumes. The experiment rejects the separate late width
LUT patch combination at assembly time; that patch would otherwise modify only
the old Chip copy. It remains inside the existing CUSTOM2/hardware gates.

`c-road-fast-copy` verifies all 468 bytes at the actual target `$9fd5e0`.
`c-road-fast-fullvar` matches all 14,023 hashes, all 52 sound requests and the
recorded authoritative terminal ranges against `c-fullrace1`, including finish
13835, exit 14024 and a fresh next race. Thus the tested relocation preserves
simulation outcomes through the successful-finish tape.

However, the paired cached cycle-exact 020 cost runs show no throughput benefit:
`c-road-base-cost` renders 192 frames over fields 100–1000, while
`c-road-fast-cost` renders 191 (10.667 versus 10.611 fps). Both start with 29
frames and cursor 100; different later live-field states reflect progress within
the current tick and are not used for equivalence. The standard 500-field
candidate result is 9.9 fps. This is not evidence for enabling the optimization
in normal C, and no such promotion is made. The loop contains repeated divides
and is compact enough to fit the 020 instruction cache; the measured result does
not prove which cost dominates. Broader CPU/cache testing belongs to any later
D3 evaluation. The normal slave remains 7,708 bytes with its previous SHA-256.

## Current physics profile and rejected collision-gate relocation

`c-runtime-physics-profile` profiles the actual 7,708-byte normal slave on the
cached cycle-exact 020 over fields 100–600. Physics/AI PCs `$8b486..$8eff7`
account for 31.247% of total recorded units. The actor-pair collision entry
`$8c8ae` executes 13,972 times; 1,266 checks reach `$8c8f8` for detailed testing.
The initial distance gate accounts for 1.522% and the rejection tail for 0.536%.
The tail executes 13,972 times, including pairs rejected by later detailed tests.
These are flat-PC costs, not inclusive call-tree timings or universal workloads.

An experimental Fast RAM replacement duplicated the native distance gate and
its rejection tail, including both scratch-word clears, actor flag writes,
unsigned comparisons and BCLR condition-code semantics. Accepted pairs returned
to the unchanged native `$8c8f8`. The experiment preserves all 14,023 full-race
hashes, 52 sound requests, recorded terminal authoritative ranges and finish/exit
boundaries, and restarts correctly (`c-collision-gate-fullvar`).

It does not improve performance: `c-collision-gate-cost` renders 189 frames over
fields 100–1000, compared with the matching lean reference's 192 (10.500 versus
10.667 fps). The standard candidate window measures 9.8 fps. The source change
was removed after measurement; its exact patch is retained with the private
candidate build for reproduction. The normal slave remains unchanged. This
rules out promoting this small relocation as C's next performance fix; the
current profile shows substantial remaining cost spread across the wider
physics/AI routines rather than concentrated in this gate.

## Revised steering: arrest, successful finish and current response

The revised quarter-displacement model now has separate ordinary-control tapes
for arrest and successful finish, using the integrated Fast RAM object projection.
The host driver only sends joystick inputs; it does not change game state,
course length, damage, finish flags or timers. Inputs are recorded at ten-field
boundaries and the replay reads that interval from the tape.

The first driver releases throttle above speed 10,000 and does not attack.
`c-steering-finish-drive` ends with the native BUSTED screen at field 8378,
not a finish. Its 8,377 hashes and all 241 sound requests match
`c-steering-arrest-var`, which replays the same inputs with 2/3/4/12/16-field
render intervals. The recorded terminal authoritative ranges match and both
start another race with capture cleared. All 272 sampled crash states have a
zero steering residual. This establishes arrest/restart coverage; it is not
counted as successful-finish evidence.

The second driver uses full throttle, no attacks, a road-relative lane target
of 96, a 32-unit dead zone, and one sample of lateral trend to release steering
earlier. `c-steering-finish-lane` finishes at simulation field 12634 and exits
at 12823, publishing 12,822 step hashes and 24 sound requests. The inspected
finish image shows rank 1, and the next-race image renders correctly. Of 1,273
samples, 20 are airborne, one has the skid flag, and all five crash states occur.
All 113 sampled crash states have zero residual; all sampled residuals stay
strictly between -4 and 4. Sampling does not prove every intermediate state.

Fresh visible-response pairs in `c-steering-integrated-projection-visible` use
this steering model with the current Fast RAM object projection. All eight
estimates are identical to the earlier quarter-model measurements:
260/240/220/200/180/260/240/220 ms, median 230 ms, versus B's 200 ms median.
The cost reduction therefore does not establish a visible-response improvement
for these injection phases. These remain capture-end estimates with one-field
uncertainty. The normal slave is unchanged; steering remains diagnostic.

`c-steering-finish-lane-var` replays the successful tape under varying render
intervals. All 12,822 hashes, all 24 sound requests, the recorded terminal
actor/clock/spawn-timer/camera/rank ranges and finish/exit times match. It starts
a new race with capture `(98,97,0,1)`. This closes successful-finish/restart
coverage for the revised steering model; remaining baseline handling, latency
and normal-runtime integration work are not implied to be complete.

## Integrate conserved one-field steering in the runtime

Normal and lean runtime builds now select `C_STEERING`. Full-snapshot diagnostics
retain `VERIFY_C_STEERING` as an explicit alias for reproducible older references.
The implementation is renamed to `steering.s`, with the Makefile dependency
updated while preserving its original line endings. Its calculations are
unchanged: evaluate native heading/ground displacement at the four-field
reference, retain native grip/rounding, integrate one quarter per simulation
field, and clear the residual on initialization or crash. All three hooks stay
inside the master-toggle/hardware-selected C patch list.

The rebuilt full diagnostic `c-steering-runtime-full-build` is byte-identical
to `c-steering-finish-build`, so the previously verified successful-finish and
arrest tapes exercise these exact diagnostic instructions. Normal-build tests
are separate: `c-steering-runtime-off` and `c-steering-runtime-chip` inspect the
three steering entries in addition to the other enhanced hooks and retain the
original instructions. The actual normal A500 run matches B's distance and
final state hash exactly at 8.5 fps. CD32 steering/release, pause at active field
161 and resume at 172 pass with intact stack guards (344 observed bytes used).
Both integrated lean 040/060 MMU race checks verify enabled translation.

The normal cached 020/030/040/060 matrix measures 10.0/12.5/16.6/18.5 fps in the
standard window. Relative to the preceding normal build, only 060 changes
(from 18.9). These results and the remaining A4 differences are retained rather
than described as B-equivalent performance. The normal slave is 7,920 bytes,
SHA-256 `60ef76f312d7f08ce067b5a6b32966bb47f074ee78fd1166bd1cd1e0a7916bdb`.

`c-steering-runtime-visible` tests eight fresh neutral/RIGHT pairs against the
actual normal binary. Each pair starts with identical snapshots. The capture-end
estimates are 260/240/220/200/180/260/240/220 ms, median 230 ms, matching the
candidate rather than uncorrected C's 370 ms median. B's median remains 200 ms;
this integration improves C but does not close the remaining response gap.
All five standard-window normal configurations retain lateral position 160
under neutral steering, including the accelerated paths. No delayed interpolation
or extra presentation wait is added.

## Broader AI relocation: external-call overhead experiment

The next audit covered `$8d2c0..$8d8cf`: 1,552 bytes, 422 contiguous decoded
instructions. There are no PC-relative data accesses inside this range, but 25
word-sized relative transfers leave it for nine native targets. The following
native code reads mutable PC-relative tables, so the experiment deliberately
ends before that code and returns through an absolute jump at `$8d8d0`.

A private diagnostic copied the block before patching its four public entries
(`$8d2c0`, `$8d40a`, `$8d46e`, `$8d4e6`). External relative operands were adjusted
to nearby absolute-JMP stubs; indirect dispatch pointers and all data remained
native. `c-ai-fast-copy` checks every copied byte after accounting for the 25
fixups, all four entry targets, each stub's destination, and the fallthrough
jump. The exact candidate patch and helper source are retained with
`c-ai-fast-build` for reproduction.

The cycle-exact cached-020 cost result is worse: `c-ai-base-cost` renders 193
frames over fields 100–1000, versus 187 in `c-ai-fast-cost` (10.722 versus
10.389 fps). Each result subtracts its own initial frame count (29 and 28).
The additional cross-block jumps are a plausible cost, but this experiment does
not isolate their contribution from code layout/cache effects. No full gameplay
regression acceptance is claimed from the copy audit or short cost run.

The experimental source has been removed, leaving the normal runtime unchanged.
This result argues against further partial AI copying with the same stub design.
The audit also identifies an algorithmic opportunity for later measurement:
`$8d966` executes 3,538 times in the current profile, while its loop reloads the
unchanged current actor's speed/direction 14,502 times. Hoisting invariant reads
would reduce actual work rather than merely relocating it; register preservation
and the interrupted-input ownership still need checking before implementation.

## AI invariant-read experiment: no throughput improvement

Two private implementations tested hoisting the current actor's signed speed
out of `$8d966`'s scan. Neither the native loop nor its callees write that actor's
speed/direction; the loop has no callees, and the per-field input path contains
no speed/direction-field writes. D5 was saved and restored, with MOVEM on return
to preserve the final native condition codes. All original comparisons, table
selection, division, output registers and minimum-time updates were retained.

The first version moved the scan into Fast RAM. `c-ai-invariant-cost` produces
191 frames over fields 100–1000, versus the matching reference's 193. The second
keeps the loop at its native addresses: an entry wrapper saves/derives D5, calls
the original body, then restores D5. A MOVE/BRA replaces just the repeated
speed/sign calculation. `c-ai-invariant-inline-cost` produces 192 frames.
Both start with 29 frames. Their finish positions at arbitrary live checkpoints
are not used as equal-boundary proof.

Neither variant supplies evidence of a throughput gain, so both were removed
without promotion or a claim of full gameplay equivalence. Exact helper sources,
the final patch and tested binaries remain in their private build directories.
The normal source and binary are unchanged. These results do not close C's
performance requirement; further work should be guided by an explicit remaining-
requirements audit, not continued small edits without measured benefit.
