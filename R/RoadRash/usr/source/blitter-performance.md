# Blitter work

## Background overlap (E1)

`blitter_queue.s` replaces the background-clear/road pair only in a validated
public main-image copy with Enhanced framerate enabled and a 68020 or later.
Six bounded descriptors clear the sky and fill the ground while the original
CPU road routine runs. Constant fills use only the D channel. The road writes
planes 0/1 below the horizon; the descriptors write planes 0–3 above it and
planes 2/3 below it. The following plane-2 mask pass waits for the entire queue.

The queue temporarily owns the level-3 vector, enables BLIT completion interrupts,
and clears BLTPRI. It drains and restores the vector, interrupt enable and priority
before returning. It falls back to the native pair for an unusual horizon,
masked interrupts, or another enabled level-3 source. Zero-height sky blits are
omitted. The 68000 and allocation/option-off paths retain synchronous drawing.
Descriptors are CPU-only slave storage; no additional Chip allocation is needed.

The coverage audit also found a missing wait at native `$b2f8e`: the hill copy
started at `$b2f8a` was immediately followed by writes to its live registers for
the cutout operation. Chip instruction fetch stalls had hidden the dependency.
The enhanced public-image path now waits before reprogramming those registers.
Without this wait, different schedules produced small, persistent plane-2 edge
artifacts. With it, 64 consecutive completed four-plane framebuffers match byte
for byte between native synchronous and overlapped rendering at the same game
fields (040, fixed four-field test cadence, seeded simulation).

Local evidence: `tmp/dev/tmp/e-control-v4-frames` and
`tmp/dev/tmp/e-background-v5-frames`; native-channel and destination-only clears
both passed this comparison. Normal-build smoke checks cover 68000/1 MiB,
68020 Chip-only/Fast, 030, 040 and 060. Earlier timing samples are provisional
until the final E matrix; full-race and other E checks are tracked separately.

## Dial coverage (E4c)

The proposed redundant fills are necessary. In `$b4c8e`, the first fill starts
at `$b4da4`. BLTDPT advances by the full rectangle height; the opaque copy at
`$b4dc4` does not reset it. The other three planes repeat this arrangement.
For a 64×16 dial this is a 672-byte advance (16 lines at 42 bytes/line).
The fill and copy therefore cover adjacent rectangles. Keep these fills; the
original estimated 0.55% saving does not apply.

## Cached bob masks (E3)

After public relocation, `$80010..$bc3eb` is no longer executable/data storage
for the running main image. E3 reuses that Chip area for masks, preserving the
entry trampoline at `$80000` and the native heap beginning at `$bc3ec`.
A bounded 2,048-entry CPU-only lookup table adds 32 KiB to the optional public
reservation (436 KiB at this checkpoint, 564 KiB with E5 below). Cache/table exhaustion keeps the native bob path.
No 2 MiB Chip requirement or additional player option is needed.

Image loads invalidate the cache. Race preparation builds masks before the
priming render/input history starts; a subsequent load rebuilds before drawing.
Each mask is the OR of the four original bitplanes. Cached draws omit both
mask-generation blits and use the precomputed plane directly, with separate
source/mask modulos for clipping and shifts. Split/unsupported draws retain
the native path. Native recolour word exchanges update the corresponding mask
word immediately; cache entries are never used while invalidated.

In the first race, 1,400 entries occupy 152,966 Chip bytes. All cached words
matched the live four-plane source OR at race fields 101, 300, 600 and 1,000,
including recoloured images. Evidence: `tmp/dev/tmp/e-mask-audit-v2`.

## Reduced sky clearing (E4a/E4b)

Opaque mountain copies overwrite the sky band in planes 0/1; the hill copy
replaces the corresponding band in plane 2 before its cutout. Reproducing the
native signed-height arithmetic gives each clear its required end row.

Two conservative full-width dirty rectangles track the buffers separately.
The road/ground boundary and scenery seed each rectangle; clipped bob writes
extend it upwards. Subsequent clears skip untouched rows above that rectangle.
Race preparation resets both histories. Unknown buffers, native CPU rendering,
unusual horizons and overlays retain conservative clearing. No cleared row is
assumed to remain clean merely because the other buffer was clean.

The combined masks/recolour/sky changes match all 64 reference framebuffers
byte for byte (`tmp/dev/tmp/e-dirty-v2-frames`). Full-race fixed/varying cadence
runs also match the completed D reference: 16,230 simulation hashes, 72 sound
events, native finish time 16,042, end time 16,231 and identical captured actor,
clock, camera and rank ranges. Both restart checks pass. Evidence:
`tmp/dev/tmp/e-masks-dirty-finish-{fixed,vary}`. These are emulator checks.

The larger diagnostic build required moving the C patch list nearer its
handlers and making the collision initializer call independent of 16-bit branch
reach. This prevents WHDLoad patch-destination wrapping in full hash captures.

## Bob queue decision (E2)

A local 16-slot descriptor-ring prototype overlapped bob preparation and drawing.
It did not justify its interrupt and descriptor overhead: normal smoke samples
fell from 29.9 to 28.7 fps on 040 and from about 30.5 to 29.4 on 060. A controlled
030/50 comparison stayed at 25.0 fps. Forcing the same background-overlap path
on both 68000 experimental controls gave 9.7 fps synchronously and 8.1 queued;
these are prototype numbers, not the shipping 68000 path. The general bob ring
is not retained. Background completion queuing ships, bob submission remains
synchronous, and mask caching / CPU drawing remove more work instead.
Evidence: `e-bob-smoke*` and `e-queue-cost.json` under `tmp/dev/tmp`.

## CPU drawing and final memory policy (E5)

On 040/060, `cpu_bobs.s` uses the native five-width CPU cookie-cut dispatcher
for cached images at most 80 pixels wide. A bounded 128 KiB public pixel cache
provides the source planes; masks are computed in registers. Wide, split or
uncached images retain the blitter. Drawing waits for outstanding blits and
updates the dirty-buffer history. Recolour exchanges update both cached planes
and masks; image loads invalidate both caches.

The optional public reservation is now 564 KiB (`$8d000`): D's 404 KiB, the
32 KiB mask index, and 128 KiB pixels. The Chip requirement remains 1 MiB.
Blitter masks remain in reclaimed Chip memory; DMA never uses the public copies.
The 99-field bus capture (`e-public-bus`) found no DMA access into this allocation.
All live cached masks and CPU source images matched their original Chip sources
at four checkpoints (`e-final-mask-audit`).

On 020, maintaining recoloured masks erased the saving. That CPU caches static
images but retains native mask generation for mutable bike/rider images in
`$19a7e..$5c2cb`. Recolour caching starts at 030; CPU pixel drawing starts at 040.
No additional option or presentation delay is introduced.

## Final emulator validation

Normal-build sampled race rates (PAL, Enhanced framerate enabled):

| Configuration | fps |
| --- | ---: |
| 68000, 1 MiB | 8.5 |
| 68000, with Fast RAM | 8.8 |
| 020, Chip only | 12.5 |
| 020 + Fast, default / Cache | 18.4 |
| 020 + Fast, NoCache | 16.6 |
| 030/50, default / Cache | 39.4 / 39.0 |
| 040/25, default / Cache | 49.4 / 49.4 |
| 060/50, default / Cache | 49.6 / 49.6 |

These are emulator workload samples, not guaranteed minimum rates or real-hardware
measurements. Evidence: `e-final-matrix/matrix.json`, `e-020-gate-check/matrix.json`
and `e-final-extra-000-fast`. The final 020 selection was checked separately after
the matrix; it does not change the 030+ rendering policy.

Final fixed/varying-cadence runs match D's 16,230 per-tick hashes, 72 sound events,
finish time 16,042, end time 16,231, terminal state ranges and restart behavior
(`e-final-finish-{fixed,vary}`). Thirty-two complete framebuffers across the driven
race, fields 500 through 16,000, match the synchronous reference exactly
(`e-scenes-v2-{reference,candidate}`). This covers later scenery, turns and crashes.

Keyboard, CD32, pause/resume and demo checks pass. 040/060 MMU tests pass with and
without emulated data caches, including write-through Chip mappings, copyback
Fast code/stack and stack guards (`e-functional-complete-*`, `e-final-dcache-*`).
Option-off 020/040 and native 68000+Fast checks also pass (`e-final-extra-*`).

Paired neutral/right-input captures at eight consecutive input phases give
visible-response upper estimates of 120–160 ms on cached 020 (median 140 ms)
and 100 ms on 040 (all phases). The corresponding accepted C results were
120–180 ms (median 150 ms) and 120–140 ms (median 130 ms). These screen-capture
estimates have one PAL field (20 ms) uncertainty; they measure total visible
response, not added buffering. E adds no presentation buffer or simulation delay.
Evidence: `e-visible-{020,040}/results.json`.

Step E is complete under emulator validation. Real 040/060 hardware cache and
coherency checks remain pending under the existing agreement.
