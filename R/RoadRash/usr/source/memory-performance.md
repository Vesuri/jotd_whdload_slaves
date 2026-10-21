# Cache, priority and public-memory work

Step D is in progress. All runtime changes use the existing Enhanced framerate
selection. Hardware cache/coherency testing remains pending by agreement;
emulator checks do not establish real-board timing or bus coherency.

## Cache boundaries (D1)

The enhanced path requests instruction/data caches and write-through BaseMem
through `resload_SetCPU`. It preserves the slave/ExpMem policy and respects
WHDLoad `NoCache`. The original, 68000 and Chip-only paths do not make that call.

WHDLoad's supplied autodoc documents automatic cache flushing before return
from `resload_LoadFile`, `resload_LoadFileDecrunch`, `resload_Patch` and
`resload_SetCPU`. This covers the initial boot load, both intro patch callbacks,
the main loader/patch callbacks, passwords, and `ReadSomeFile`. The existing
code-copy initializers also flush after writing their code and entry redirects.
Adding a second flush after each of these API calls is unnecessary.

The game's native Ice! depacker does not use those APIs. Its common exit at
main-image offset `$3284e` now restores the original saved registers, flushes
through WHDLoad, and returns with registers and condition codes preserved.
Both packed and non-packed inputs use this exit. The patch is installed only
on the selected enhanced path. The image RLE decoder writes graphics rather
than executable code; its output remains in the DMA-compatible Chip mapping.
Boot/intro executable transitions occur before enhanced cache setup and already
pass through the loader's patch-and-flush callbacks.

VERIFY adds a separate `RRDCPU01` sidecar: previous SetCPU policy at +8,
immediate post-call CACR at +12, call count at +16. It does not change the
existing A instrumentation ABI. The post-call register equals the later race
register in every selected test cell:

| Configuration | Post-SetCPU CACR |
|---|---:|
| 020 Fast, default / Cache | `$1` |
| 020 Fast, NoCache | `$0` |
| 030 default | `$2111` |
| 030 Cache | `$2011` |
| 040/060 default or MMU | `$80008000` |
| 040/060 Cache | `$8000` |
| 040/060 NoCache | `$0` |

The 68000, Chip-only 020 and disabled-toggle controls record zero setup calls.
The 040/060 result confirms that the CACR alone does not explain throughput:
the default already enables both caches, while WHDLoad Cache produces a
different inherited policy. Page attributes and the accelerator's Chip/IO
cache-inhibit signals also matter; do not infer hardware performance from these
emulated register values.

Both 040/060 MMU probes inspect every 4 KiB BaseMem page in supervisor and user
tables: all 512 descriptors are write-through, never copyback. The relocated
code and stack pages are copyback. These checks pass with emulator data caches
disabled and enabled, and stack guards remain intact. The data-cache-enabled
cases are functional checks, not comparable hardware performance measurements.

Local evidence under ignored `tmp/dev/tmp/`:

- `d-cache-matrix-validated`: 16 successful cache-state/gating configurations.
- `d-native-decrunch-build`: normal and diagnostic builds with the exit fix.
- `d-decrunch-normal-matrix`: all 11 normal configurations reach and run the race.
- `d-cache-functional-*`: MMU page policy, keyboard, CD32 pause and demo-to-race.
- `d-cache-data-enabled-*`: page policy with data-cache emulation enabled.
- `d-cache-data-race-*`: both data-cache-enabled MMU cases run the full
  500-field race window successfully.

The normal build is 20,648 bytes, SHA-256
`bfc5be1c0628e85961a7bf548aa9a21b6d194d31ddac43fccdd80c3b26c2696a`.
Measured fps: A500 8.5, Chip-only 020 12.5, Fast 020 default/Cache 12.5,
Fast 020 NoCache 8.3, 030 16.7, 040 22.7, 060 23.1. The minor 040/060 changes
from C's 22.8/23.3 are retained measurements, not claimed gains. No simulation
or input-timing algorithm changed.

## Blitter priority (D2)

The boot loader's temporary copper list starts at loader offset `$427c`
(loaded at `$467c`). Its MOVE at offset `$42e0` writes `DMACON=$87d0`,
including BLTPRI. Main initialization installs that list before switching to
the game copper list. The previously suspected CPU writes at main offsets
`$2879a` and `$2882e` enable other channels; neither sets BLTPRI.
The dynamic sprite-enable write at `$2f224` also does not set it. The native
priority-clear routine at `$2eacc` is not called in the tested race path.
The initialization list and before/after initialization samples are retained
in `d-priority-loader-copper`.

Equal-layout diagnostic builds differ only in the three priority immediates.
Each pair uses the same 500-field window and records DMACONR before and after:

| Configuration | Priority set fps | Priority clear fps |
|---|---:|---:|
| A500 | 8.5 | 8.4 |
| Chip-only 020 | 12.5 | 11.9 |
| Fast 020 default | 12.4 | 11.9 |
| Fast 020 Cache | 12.4 | 12.1 |
| Fast 020 NoCache | 8.3 | 8.3 |
| 030 default / Cache | 16.7 | 16.7 |
| 040 default / Cache | 22.7 | 23.2 |
| 060 default / Cache | 23.1 | 23.5 |

Consequently only the selected enhanced 040/060 path clears BLTPRI at race
preparation/reset. It saves the previous bit once and restores it when the
native race/demo hook is removed. The 68000, 020 and 030 retain the native
priority. There is no per-tick write and no extra user option. This decision
must be remeasured after relocation or blitter scheduling changes.

Normal-build helpers live after the hot simulation code. An intermediate
layout cost the 020 0.2 fps; moving these helpers restored 12.5 fps. The final
20,772-byte build is SHA-256
`5e514ea2bffd72b807aeab18697a369c6ee571bdff73c10e4fc738416d54af54`.
Its normal matrix measures 23.2 fps on 040 and 23.6 on 060, with unchanged
rates on the remaining cells relative to D1. These are emulator results.

Evidence: `d-priority-matrix` (22 equal-layout runs),
`d-priority-tail-matrix` and `d-priority-tail-remaining` (all 11 final normal
cells), and `d-priority-tail-functional-*` (MMU page policy, controls,
demo exit/restart). The demo test explicitly checks priority clear during
the demo, restored after exit, and clear again in the following race.

`d-priority-finish-fixed` and `d-priority-finish-vary` reproduce all 16,230
accepted C simulation hashes, 72 sound events, and all six terminal state
regions. Finish occurs at field 16,042 and exit at 16,231; both restart with
clear capture/fraction state. A separate older tape ends in arrest and also
matches across both cadences (7,006 hashes, 19 events); it is not the accepted
finish tape and is not compared as though its inputs were identical.

## Main-image relocation investigation (D3, not yet enabled)

The native `rr.ice` output is a single HUNK_CODE image, not a flat binary
without relocation information. Capturing it before the loader's relocation
at `$4936` gives 267,508 bytes, SHA-256
`f028a869b517fc31dfd57dfdffab0b742901b98b6d0b9cfc70322447a6d72924`.
Its executable/data payload is `$3c3ec` bytes (246,764), with 5,173 unique,
even, bounded HUNK_RELOC32 offsets. The sole target at the payload endpoint
is the heap-start operand at offset 6. Keep that target at the original Chip
heap `$bc3ec`; it must not follow the CPU image into public RAM.

After native relocation, the relocation block remains at `$bc40c` and its
offset array starts at `$bc418`. A private prototype copies the already
patched image and remaps its typed relocation operands, the existing C code
copies, and explicitly identified slave operands. It preserves the original
heap and does not reclaim the old image. This is feasibility evidence, not
a completed allocation, DMA, or module-lifetime audit.

### Numeric alias in the opponent lane table

The six signed coordinates at `$8d128` are followed by a function pointer
at `$8d134`. Native lane searches permit index 6 (`$8d81e/$8d85a` reject
indices >= 7). The lookups at `$8db42` and `$8db7e` consequently read the
high word of that pointer as a seventh coordinate: originally `$0008`.
Relocating the executable pointer changes that numeric value. The scalar
lookup and executable pointer must therefore be separated while preserving
the original seventh coordinate; treating every use as a pointer is wrong.

The uncorrected prototype first differs at simulation tick 9,763, in the
steering word (+`$46`) of actors 13 and 15. CPU write traces identify
`$8dba6`, and paired state captures agree through tick 9,762. For actor 13,
the following steering value changes from -101 to +28 while the divisor
remains 287. This is a relocation defect, not acceptable RNG variance.

The corrected private lookup preserves coordinate 8. Both fixed and varying
render cadence reproduce the accepted 16,230 simulation hashes, 72 sound
events, six terminal state regions, finish field 16,042 and exit field
16,231. Restart clears the captured simulation/fraction state. No speed or
latency acceptance criterion was relaxed.

Local evidence: `d-original-hunk` (captured HUNK, typed relocation inventory,
conservative control-flow inventory and short race DMA sample),
`d-public-snapshot-{reference,public}` (tick 9,762),
`d-public-snapshot-next-{reference,public}` (tick 9,763),
`d-public-writers-{reference,public}` (CPU writes and source table), and
`d-public-lane-finish-{fixed,vary}` (corrected full races). The earlier
`d-public-finish-*` / `d-public-v2-finish-*` results are rejected prototypes.

Remaining before promotion: validate the relocation block before changing
anything; cover all supported slave/copy references; audit DMA over loading,
menus and race transitions; audit all other modules and loaded assets;
verify public-memory sizing, placement and fallback; remeasure blitter
priority; and repeat the final normal-build and functional matrix. D3 is
still open. Real-hardware cache/coherency validation remains pending by the
user's explicit choice; emulator validation is the current scope.

## Main-image implementation and emulator validation

The normal enhanced 020+ Fast path now relocates the complete main payload,
including menus, simulation, rendering, interrupt/audio code and CPU data.
`public_main.s` validates the HUNK type, target, count, trailer and every
aligned in-range operand offset before any relocation writes. Unavailable or
unsuitable optional memory, or a malformed table, retains the native main
image. `public_refs.s` contains explicit slave-operand annotations; it never
scans arbitrary numeric values for apparent addresses. Older experimental
copies with unaudited references are rejected at assembly time when combined
with this feature. Full snapshot diagnostics select `VERIFY_D_PUBLIC_MAIN`.

The optional allocation is 320 KiB. Its first 20 KiB retain the existing
16 KiB guarded supervisor stack and spacing; the 246,764-byte main payload
begins at offset `$5000`. The remaining 60,436 bytes are reserved headroom.
The Chip requirement remains 1 MiB. The original main image and heap remain
allocated; no stale Chip storage is reclaimed. The enhancement toggle, 020+
selection and actual Fast-memory placement gate all relocation writes.
The implementation accepts the normal Zorro II and upper 32-bit Fast windows.

Native portrait loads at `$a5de0` were followed to their consumers. The SET
relocator at `$afd9c` builds image pointers, and the portrait renderer at
`$b0ce4` copies pixels into Chip screen planes using CPU byte loops. Thus this
portrait lifetime does not require the scratch image itself to remain Chip.
Four 19-field portrait-menu DMA captures and inspected screenshots pass
(`d-public-menu-v3-fixed`). The broader graphics/load audit remains open;
this evidence does not classify every shared image consumer as CPU-only.
`d-public-load-v2-fixed/loads.json` records 29 file loads through a complete
race, with preserved filenames, sizes and destination addresses.

The normal 22,180-byte build has SHA-256
`f440dc05b67b65329675b2343bc414cffd756d3c049e8a41f27dddb754994136`.
`d-main-hardened-matrix` passes all 11 normal cells:

| Configuration | Frames/s |
|---|---:|
| A500, 1 MiB | 8.5 |
| Chip-only 020 | 12.5 |
| Fast 020 default / Cache | 16.7 |
| Fast 020 NoCache | 16.6 |
| 030 default / Cache | 25.0 |
| 040 default / Cache | 25.2 |
| 060 default / Cache | 28.6 |

`d-main-promote-build` is byte-identical to the tested normal and lean MMU
builds. `d-public-functional-*` passes 040/060 MMU policy, stack guards,
keyboard/CD32 input and demo transitions. `d-public-extra-v2-off-*` passes
with the toggle disabled. `d-public-no-allocation` and
`d-public-odd-relocation` inject missing allocation and an invalid odd
relocation offset respectively: both run the full short window with the
original main entry, without a partially installed relocation.

`d-public-promote-finish-{fixed,vary}` repeats the accepted 16,230 hashes,
72 sound events, six terminal regions and finish/exit fields exactly, and
restarts cleanly. The input-replay probe (`d-public-extra-v2-latency`) applies
field-301 input to simulation tick 301; it uses a diagnostic configuration
without measured heading prediction because those probes share native hooks.
The separate **normal-build** visible-response test uses eight paired
neutral/RIGHT injections with identical initial states. Estimates are
140/120/160/140/120/160/140/120 ms (median 140 ms), including gameplay response
and capture-end uncertainty; these are not an artificial presentation delay
or a measurement of host-display latency. Evidence: `d-public-visible-020`.

This closes the main-image implementation only. D3 still needs the remaining
bootstrap/low-memory and mixed-asset audit, broader CPU/memory selection and
DMA coverage. The priority remeasurement below retains the current policy.


## D3 bootstrap code and stack

The loader, title and intro now also use the optional public allocation when
Enhanced framerate is enabled and WHDLoad supplies actual Fast RAM. This
bootstrap path uses 68000 instructions and does not require the later 020+
simulation selection. The disabled toggle and unsuitable/missing allocation
retain the native boot path. No additional memory is requested.

| Allocation offset | Lifetime/use |
|---|---|
| `$00000..$04fff` | Existing main supervisor stack, guards and spacing |
| `$05000..$413eb` | Title, then intro, then the complete main image |
| `$42000..$48fcf` | 28,592-byte loader image and four external-call stubs |
| `$49000..$4d01f` | Separate 16 KiB boot supervisor stack with guards |
| `$4d020..$4ffff` | Remaining headroom |

The loader must survive both title and intro, so its copy does not share their
buffer. Its original stack is replaced with the separate guarded boot stack;
the main stack initializer can then fill its own guard region without
overwriting active startup frames. The observed boot high-water use is 220
bytes in the complete intro-to-race test, with both guards intact. This is a
measured run, not a proof that every possible interrupt nesting fits.

`public_loader.s`, `public_boot.s` and `public_boot_tables.s` describe typed
relocations for `lomain.ami`, `TITLE.AMI` and `INTRO.AMI`. The audit followed
1,781/1,203/1,297 decoded instructions respectively, with explicit interrupt
and dispatch roots. It also accounts for title palette pointers and intro
palette, dispatch and callback pointers stored in data. These tables are not
a numeric pointer scan. Every rewritten absolute operand and PC-relative
instruction is checked against its native value before copying or publishing;
a mismatch retains the original module. Each published copy flushes caches.

Copper remains at its original Chip addresses: title `$86c8..$878b` and
`$128a8..$1294b`, intro `$8904..$8a67`, loader `$4cc4..$4d5f`.
The title/intro temporary startup lists matter even though they disappear
from steady-state traces. PC-relative copper LEAs use appended stubs;
loader PC-relative calls to the separately loaded `$8000` module use stubs
that preserve the return address. The shared loader address `$4c98` and low
fixed control cells remain authoritative in Chip and are still part of the
broader low-memory audit. The original `$400` entry is not overwritten: a
six-byte jump would corrupt the adjacent fixed control cell at `$404`.

The 25,680-byte normal build SHA-256 is
`ee6801d40db40b8e49c5830314b8f939264d07e49b88e55941f851cb0ee65f4d`.
`d-public-boot-promote-build` is byte-identical to `d-public-boot-layout-build`.
The all-11-cell `d-public-boot-layout-matrix` retains the preceding main-image
rates exactly. `d-public-boot-layout-functional-*` passes 040/060 MMU policy,
main stack guards, keyboard/CD32 and demo transitions.
`d-public-boot-extra-{off-020,off-040,000-fast}` also passes toggle-off and
native-68000-with-Fast short-race checks.
`d-public-boot-layout-finish-{fixed,vary}` matches the accepted 16,230 hashes,
72 sound events, six terminal regions, finish 16042 and exit 16231, and
restarts cleanly. No simulation acceptance rule changed.

`d-public-loader-sequence-layout-v2` captures title, intro, seven later intro
stages and entry into a race. Title and intro screenshots have the exact
native PNG hashes; DMA traces retain the Chip copper lists. The boot guards
are intact. `d-public-boot-negative` deliberately mismatches the first check
for all three modules: title/intro retain their native entries, the complete
intro still runs, and the independently validated main image still relocates. Earlier entry polling sometimes missed the title and reached the
intro; those failed probes are retained and are not positive evidence.
An earlier private validation-table generator also modified the copy loop
twice; it was discarded. Full diagnostics require the tables after runtime
code so WHDLoad's signed-word patch-target offsets stay in range.

## D2 remeasurement after the main-image move

`d-public-priority-matrix` compares equal-layout builds differing only in the
priority-selection immediate. Priority on/off rates are 16.7/16.6 on Fast
020, 16.6/16.2 with NoCache, 25.0/25.0 on 030, 25.0/25.2 on 040 and
25.1/26.8 on 060. Cache variants give the same decision. Keep native priority
on 000/020/030 and clear it on enhanced 040/060. These diagnostic-layout
rates are not interchangeable with the normal-build 060 rate of 28.6.
The main-image normal build also passes the 030 Zorro III Fast-only short
race (`d-public-z3`, 25.0 fps).

D3 remains open for the low fixed-address data, other mixed CPU/DMA asset
consumers. The native-68000 main-code/stack path is completed below. Real-hardware
040/060 cache coherency remains pending by agreement; the evidence above is
emulator validation.


## D3 native 68000 main image and stack

Main relocation now has its own Enhanced-framerate/Fast-placement gate,
independent of the 020+ simulation selection. A 68000 with Fast RAM uses the
same main-image relocation and guarded supervisor stack while retaining its
native simulation. C-only copied routines are remapped only when that path
was actually initialized. No cache instruction is introduced on the 68000.
Memory reservation and Chip fallback are unchanged.

The normal 25,728-byte build SHA-256 is
`07d21cf0f12f23e0383b1cc5a91baa1dc998b6dbd8d26aaea174f805eb3b3c61`.
`d-native-main-promote-build` is byte-identical to the tested normal
`d-native-main-public-build`. On the native A500 plus 8 MiB Fast configuration,
`d-native-main-normal-*` measures 8.4 fps before and 8.8 fps after. Fast 020
and 060 retain 16.7 and 28.6 fps respectively. This is an emulator result;
bootstrap timing and native randomness can change the free-running distance,
so functional equivalence is checked separately at an equal cadence.

The private native comparison enables a fixed RNG seed and eight-field
presentation cadence on both builds. It does not enable C simulation on the
68000. `d-native-main-{reference,public}` matches the field-590 state hash
2069561491 and both endpoint snapshots exactly. The complete native races
in `d-native-main-race-{reference,public}` match all 178 state checkpoints,
the generated steering/attack input tape, finish/exit state and restarted
race state. Both finish, with race exit field 17874. No acceptance rule was
relaxed. `d-native-main-functional-*` passes the existing 040/060 MMU policy,
stack guards, keyboard/CD32 and demo checks for the broader selection.

`d-native-main-{keyboard,pad}` verifies steering, release, pause/resume and
both stack guards on the native 68000 path (284/312 observed bytes used).
`d-native-main-finish-{fixed,vary}` also preserves all accepted enhanced-path
16,230 hashes, 72 sound events, six terminal regions, finish/exit fields and
restart, so broadening the memory gate does not alter C's selected behavior.


## D3 image description tables

`public_assets.s` separates CPU image descriptions from the image pixels used
by the blitter. The optional public reservation is now 368 KiB: the preceding
320 KiB layout is unchanged, followed by twelve 2 KiB slots for the typed
owners at `$432..$45e` and three 8 KiB slots for fixed-address image sets.
A slot holds its original load address and the descriptor array; pixels are
not copied and their pointers continue to address Chip RAM. Old Chip storage
is retained, including the sprite alias described below.

The native `$afd9c` relocation runs first with its original register/CCR
results. A complete bounded descriptor copy is then published through the
known owner. A reload using that public owner is translated back to its
original Chip destination before native size/depack logic runs. For the
fixed level-object/opponent-bike/player-bike sets, twelve audited renderer
LEA operands are updated only after the copy, then caches are flushed.
Loader/depacker operands stay native. No per-frame pointer wrapper is added.
If a later fixed-address asset exceeds its slot, its readers are restored to
the native table rather than retaining a previous public copy.

The native depacker was used to unpack all 67 assets in an isolated harness
copy (`d-unpack-assets-v2`); every resulting size was checked against the Ice
header or original uncompressed size. WHDLoad's generic decrunch API alone
left these Ice files packed, so the earlier `d-unpack-assets` capture is not
used as unpacked evidence. The descriptor audit (`d-image-format-audit.json`)
covers 22 sets and confirms every pixel offset is beyond its descriptor array.

| Set owner/family | Images | Descriptor bytes |
|---|---:|---:|
| Flag / common player / common opponents | 27 / 106 / 106 | 380 / 1,486 / 1,486 |
| Police / car 1 / car 2 | 45 / 54 / 18 | 632 / 758 / 254 |
| Mirror 1 / mirror 2 | 63 / 27 | 884 / 380 |
| Player crash / opponent crash | 98 / 63 | 1,374 / 884 |
| Player/opponent wheel replacements | 49 each | 688 each |
| Level objects 1–5 | 369 / 315 / 333 / 324 / 450 | 5,168 / 4,412 / 4,664 / 4,538 / 6,302 |
| Opponent bikes / player bikes | 497 / 115 | 6,960 / 1,612 |
| Level-finish / small pictures / bike-shop set | 15 / 5 / 3 | 212 / 72 / 44 |

The ordinary owner slots fit 145 descriptors and the fixed slots fit 584,
above the audited maxima 106 and 497 respectively. Size arithmetic is 32-bit
before the capacity comparison. The first two car-table words at `$467c` and
`$467e` also serve as native blank-sprite control words. They remain in the
original Chip copy. The CPU table's corresponding words are unchanged by
its consumers; recoloring changes pixel data, not these two words.
`d-public-assets-v3-dma-alias` traces 99 fields: only those two original
sprite words are read by DMA; no public header is DMA-addressed. All 15
copied tables' pixel pointers remain in Chip RAM. This is a sampled DMA
check backed by the format/consumer audit, not exhaustive execution coverage.

The 26,360-byte normal build SHA-256 is
`5d8d0885f674aecd3d9f27ecfff3f6a0e97c7f0a8dc06f3233e9a789c5bb0852`.
`d-public-assets-promote-build` is byte-identical to `d-public-assets-v4-build`.
`d-public-assets-v4-finish-{fixed,vary}` retains the accepted 16,230 hashes,
72 sound events, six terminal regions, finish 16042, exit 16231 and clean
restart. The prior direct-address build also produces identical final and
restart PNGs. `d-public-assets-native-race-public` matches all 178 controlled
native-68000 checkpoints and restart. `d-assets-capacity` explicitly exercises
restoration of native readers after a public copy has already been published.
The functional matrix passes controls, demo transitions and 040/060 MMU
policy; `d-public-assets-v3-dcache-*` also enables data-cache emulation.

The ordinary machine rates remain 8.5/12.5/16.7/16.6/25.0/25.2 through the
A500, Chip 020, Fast 020, NoCache 020, 030 and 040 cells respectively. The
060 measures 28.3 fps versus 28.6 before this split. Equal-layout on/off
measurements confirm the small regression; direct operands and several
alignments do not recover it. This is recorded as a tradeoff of the broad D3
memory move, not described as a framerate gain. Real-hardware measurement
remains pending.

The final normal matrix is recorded in `d-public-assets-v4-matrix` plus
`d-public-assets-v4-matrix-tail`. The initial 040 Cache probe detected race
entry late; its retry and both 060 cells pass. The harness now validates the
public entry instruction before accepting a trampoline destination.
