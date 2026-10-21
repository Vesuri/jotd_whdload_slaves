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
reservation (436 KiB total). Cache/table exhaustion keeps the native bob path.
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
