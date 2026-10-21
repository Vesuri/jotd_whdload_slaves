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
