# CPU work reduction (F)

F1–F5 are complete under emulator validation (2026-10-21). They evaluate ways to reduce CPU work while preserving the accepted C/D/E
simulation, presentation and input behavior. Every retained patch is behind
`CUSTOM2=1` (Enhanced framerate). F6 remains future work by explicit agreement;
the D3 fixed-address exception is unchanged.

## Road rasterizer

F1a's repeated word loads replicate 16-bit patterns into both halves of a long;
they are not redundant reads that can simply be deleted. A packed-read prototype
preserved the pixels but measured exactly the same 18.4/39.0/49.2 fps as its
matched-layout control on 020/030/040. Keep the native replication.

F1b selects four specialized edge routines once per road draw from the eight
binary palette flags. Each scanline then uses the selected routine's ORs rather
than repeating eight tests and loading palette words. Background masks and
stripe selection remain native. The 256 static cases encode outer-mask bits
7..4 and inner-mask bits 3..0 for planes 0..3.

F1c rewrites the three relocated span jump tables and their unrolled fill ladders
after HUNK relocation. Each ladder writes both planes before advancing to the
next pair, eliminating a second table dispatch. Odd lengths still end with one
word per plane. Native clipping and continuations remain unchanged.

## Geometry: measured prototypes not retained

All three prototypes produced 64 opening framebuffers identical to E. Their
extra bookkeeping outweighed the removed native work in the sampled race.

| Candidate | Matched control fps: 020 / 030 / 040 | Candidate fps |
|---|---|---|
| F2a fused four edge DDAs and width/shift pass | 18.4 / 39.0 / 49.2 | 18.4 / 38.7 / 49.3 |
| F2b eight-step DDA unroll | 18.0 / 39.0 / 49.2 | 17.8 / 38.9 / 49.3 |
| F2c exact reciprocal projection | 18.4 / 39.0 / 49.2 | 16.6 / 35.5 / 46.0 |

F2a preserved native fixed-point addition order. Apparent width clamps in the
original per-line pass are dead calculations, so the prototype reproduced the
actual output rather than changing the game's width behavior. F2c cached a
24-bit reciprocal, corrected quotient/remainder exactly and fell back to DIVU
outside its bounded numerator/denominator range. Helper and correction overhead
made it substantially slower. Native geometry stays in place; the original
projected 4–6% gain is withdrawn.

## HUD

F3 remembers the displayed needle angle separately for both physical buffers,
and skips restore/draw only when that buffer already contains the correct angle.
The tachometer's native scale-state write still occurs on every call. Unknown
buffers always draw. Race preparation invalidates every key.

Only the dedicated race clock/rank text calls use the glyph cache. Entries key
on destination, glyph source and color; hits reproduce native cursor/register
side effects. The odometer shares a needle restore rectangle and must redraw.
Dials and position already have native change checks. Mirrors contain moving
object overlays: an unchanged background still needs its existing blitter clear.
No additional frame wait, input sampling delay or presentation history is added.

## Object work

F4 replaces the positive type comparison cascade with the native handler-offset
table for types $000..$233. Holes target the native return. Negative types retain
the separate native overlay path; per-object flag decisions remain in handlers.

F5a trims register saves only in the audited leaf projection helper ($8a716) and
native depth sort ($8b37e, also the fallback below). Helpers with indirect/deeper
collision calls retain their saves; $8b02e already has selective saves.

F5b's proposed distance early-out already exists in $8c8ae. It follows shared
scratch clearing and front/back bookkeeping and uses asymmetric current-position
bounds before the expensive geometry. Moving a simpler absolute-distance test
before those side effects would change behavior. Preserve the existing test.

F5c retains the previous permutation of incoming draw-list ordinals and insertion
sorts fresh keys through it. Ties use original incoming ordinal order, preserving
native stable ordering. Count changes reset the seed. Counts below two or at
least 64, and signed ranges that make the native subtraction-sign comparator
non-transitive, use the original routine. The seed never assumes persistent
object identity. In 160 captured lists, the model reproduced native order while
reducing comparisons from 17,381 to 2,968 and counted stores from 15,500 to 10,950.

## Measurements and validation

The final normal build measures the following rates over the established
500-field throttle workload. These are emulator samples, not minimum rates or
real-hardware guarantees. Small differences are sensitive to code/cache layout.

| Machine | E normal build | F normal build |
|---|---:|---:|
| 68000, Chip/Slow | 8.5 | 8.5 |
| 68000 with Fast RAM | 8.8 | 9.4 |
| 68020, Chip only | 12.5 | 12.5 |
| 68020 with Fast RAM | 18.4 | 18.6 |
| 68030/50 | 39.4 | 39.5 |
| 68040/25 | 49.4 | 49.6 |
| 68060/50 | 49.6 | 49.6 |

A same-layout control differs in only the four bytes that bypass F initialization:
18.1/39.0/49.2 fps on 020/030/040 versus 18.6/39.5/49.6 with F. Removing rejected
prototypes changed the earlier candidate's layout and its 030 result from 39.8
to 39.5; report the final build, not that peak. In-place span/save patches gave
no measured Chip-only framerate benefit and are not enabled there. Public 68000
keeps native simulation while using the retained road/dispatch/sort reductions;
HUD caching requires C's accelerated path.

The normal slave grows from 30,324 to 38,812 bytes. The optional reservation
remains 564 KiB and the Chip requirement remains 1 MiB. The additional tables,
glyph keys and sort seed are CPU-only slave storage, never DMA sources.

Validation completed:

- All 64 opening 33,600-byte framebuffers match E, including the final cleaned
  build. All 32 full-race sampled scenes match E, covering bends, hills, traffic,
  HUD changes and crashes.
- Fixed and variable render-cadence full races match all 16,230 simulation hashes,
  72 sound events, finish/time/terminal state and restart checks. The fixed race
  also matches E directly; finish time is 16,042 and end time 16,231.
- The actual sort code reproduces native stable order in 14 synthetic cases:
  ties, reversed/sorted lists, count changes, one/63/64-item lists and a signed
  overflow range. The in-slave test runs after flushing its initialized patches,
  matching the production initialization contract.
- Keyboard and CD32 steering/pause/resume, demo playback and stack guards pass.
  040/060 MMU policy and data-cache-enabled checks pass. Option-off 020/040 and
  the Chip-only/68000 paths boot and run successfully.
- Eight visible-steering phase samples on 020 give 140 ms median / 160 ms maximum;
  the 040 samples give 100 ms. These are the same conservative capture bounds as
  E, not newly introduced delay. Simulation/input cadence is unchanged.

Initialization patches run only after the existing public-image validation.
The existing public-main completion flush covers all new code writes before
execution. No patches are made per frame. Physical 040/060 cache/coherency
validation remains pending under the existing D1d agreement.

Evidence directories include `f-release-matrix`, `f-release-extra-000-fast`,
`f-release-control`, `f-release-frames`, `f-scenes-final-candidate`,
`f-final-finish-fixed`, `f-final-finish-vary`, `f-functional-*`,
`f-final-dcache-*`, `f-sort-selftest-v3`, and `f-visible-020` / `f-visible-040`. The complete-race and
functional runs preceded removal of the unused Chip-only patch path; final
normal machine, framebuffer and latency checks cover that cleanup.
Private prototype sources, builds and raw evidence remain under ignored
`tmp/dev/tmp/f-*`; no proprietary game image is added to the repository.
