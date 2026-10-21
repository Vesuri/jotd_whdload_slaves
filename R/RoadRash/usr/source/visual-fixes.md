# Original visual bug fixes (2026-10-22)

The distant-rider flicker, mirror flicker and large vertical hill jumps are
fixed independently of CUSTOM2. This follows the user's explicit authorization
to fix the original defects after the H1/H2 investigations. The 3.0b version/date
remain unchanged. No additional option, frame history or presentation delay is
introduced.

## Visibility

`visual_actor_visibility` replaces the decision block at `$89e2c`. It subtracts
full 16.16 positions before testing visibility. Forward riders are eligible at
0 <= distance < 30 segments; rear riders at -16 <= distance < 0. The existing
player-speed comparison still suppresses a close-behind rider when the player
is at least as fast, now only for -1 < distance < 0. A steady separation cannot
oscillate across a threshold merely because camera/rider segment boundaries
occur at different times.

The old cutoff blended distances 30..31 and -2..-1 according to segment phase.
The new fixed limits choose the nearer edge of each transition band. The native
integer **index difference** is retained in D0 for forward projection; replacing
that index with a rounded relative distance would misalign the road lookup.
The original rider position is restored in D2 before the existing native or
enhanced lean hook. Mirror projection, sprite selection and cleanup remain
native. Explicit helper references support relocated and unrelocated images;
all added instructions are 68000-compatible.

## Height projection and simulation isolation

After the native read/advance/wrap at `$89794..$897a0`, A1 points at the next track
interval. The hook at `$897a6` reads its height byte without advancing A1. The
fractional offset and subsequent road-point accumulation now refer to the same
interval. All consumers see the corrected height/road-Y/occlusion arrays: road,
riders, scenery and sprite clipping. Integer projection/bobbing remain; this
removes the reference discontinuity, not ordinary one-pixel raster steps.

The hook is installed **after** copying the reduced simulation geometry, so
that helper retains native instructions. The earlier investigation conservatively
identified collision-table reuse as an adoption risk. A closer consumer audit
shows why the existing reuse optimization can remain:

- `$8b29a..$8b37c` uses horizontal/depth values to accept world objects and produce
  their collision distance and scale. The height/occlusion comparison at `$8b33a`
  does not branch; subsequent moves replace its flags. Corrected vertical values
  only change draw Y and clipping height, not record acceptance or width.
- `$8c7f2..$8c8ac` consumes distance, scale, type, side/lateral metadata and original
  sprite dimensions. It never reads the projected Y or clipping-height fields.
- `$8a5fc..$8a714` likewise rejects scenery by depth and horizontal division, not
  projected height. `$8c48e..$8c582` uses scenery world positions and sprite sizes.
- Geometry reuse changes only the render-derived height/occlusion values at the
  next collision preparation; its horizontal/depth inputs are unchanged.

Full-race hash/event comparison below validates this reasoning with collisions,
crashes and restart. It does not assert every possible native variable-delta
trajectory is identical: changing rendering workload can change its cadence,
and the native rider traversal derives pose only for eligible forward riders.
The accelerated simulation retains authoritative pose ownership.

## Validation

Normal slave: 39,228 bytes, SHA-256
`55f24917ce843bddef178283acc006c09183173b5adf4998bb8c4d3cb51a6a05`. All evidence is retained in the ignored local
`tmp/dev/` harness; no original game assets are committed.

- `visibility-on-fix-straight` / `off-fix-straight`: 970 / 515 render samples.
  The previously alternating pair of far riders stays omitted throughout the
  30..31-segment trouble band: 44 / 22 checked actor samples, six draw records
  throughout, rather than alternating six/eight.
- `visibility-on-fix2` / `off-fix2`: 5,000 / 2,552 render samples including overtakes.
  The reproduced mirror rider remains drawn for all 109 / 37 checked samples in
  the -2..-1 band during the first overtake. Later crashes are not mistaken for
  visibility failures.
- `h1-on-fix` / `h1-off-fix`: 3,392 / 1,545 consecutive render snapshots through
  field 3800. An integer model exactly matches all 32 height and projected road
  Y entries in every snapshot, and player Y in all 2,993 / 1,428 snapshots where
  that player draw record exists. Crash/run animation can omit that record.
  The runs include 101 / 37 airborne snapshots, 9 / 10 track-table versions and
  both 255→256 and 511→512 wraps. The prior isolated boundary sweep reduced the
  largest reference jump from 17 to 2 pixels; the running code now matches that
  evaluated correction rather than merely predicting it offline.
- `visual-final-finish-fixed` / `visual-final-finish-vary`: both match the previous
  release's `g-final-finish-fixed` for all **16,230** simulation hashes, **72** sound
  events, terminal actor/control ranges, finish field **16042**, exit field
  **16231**, and a clean new-race reset. Forced geometry reuse is exercised.
- `visual-matrix`: normal builds pass 68000 Chip/Slow, Chip-only 020, Fast 020,
  040 and 060. The same 500-field throughput scenario retains **8.5, 12.5, 18.6,
  49.6 and 49.6 fps**, respectively. No timer, input queue or display handoff was
  changed. `visual-extra-000-fast` also passes at the previous 9.4 fps, exercising
  the relocated native-simulation path. The ordinary game screenshot has aligned
  road, rider and scenery.

- `visual-dcache2-040-mmu` / `visual-dcache2-060-mmu`: emulator data caches and
  MMU enabled; game reaches the race and the policy probe verifies all 256
  supervisor and user BaseMem pages as write-through, Fast code/stack copyback.
  An initial probe lacked its MMU sidecar and was rerun with that diagnostic
  compiled in; it was not a game failure.

The first private visibility build placed the hook beyond the signed patch-list
reach and failed to boot; the final helper is adjacent to the main patch list.
Those failed captures are retained separately and are not counted as validation.
Physical cache/coherency testing remains the existing D1d future item.
