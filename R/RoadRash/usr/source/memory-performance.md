# Cache, priority and public-memory work

The allocation figures below describe the D checkpoint. Step E increases the
optional public reservation from 404 to 564 KiB and reuses the abandoned Chip
main image below `$a5de0` for blitter masks. Menu scratch and embedded DMA
pixels retain Chip storage; see the graphics relocation correction in the
rendering document. The approved fixed-address exception is unchanged.
See [current rendering memory and validation](blitter-performance.md).

Step D is complete for the agreed emulator scope, with the explicitly approved
fixed-address-global exception below. All runtime changes use Enhanced framerate. Hardware cache/coherency testing remains pending by agreement;
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

## D3 music headers and patterns

`public_audio.s` copies the CPU prefix of each ProTracker module after native
initialization has built the sample-pointer table. Only the module-base owner
changes; all Paula sample pointers retain their original Chip addresses.
The two installation sites check the original BSET instruction and relocated
flag address before replacing it. The wrappers preserve registers and native
condition codes, including BSET's Z result, and enable playback after publication.
Unrecognized signatures or oversized prefixes retain native storage.

The main player uses a 20 KiB slot at public offset `$5c000`, bringing the
optional allocation to 388 KiB. The boot player uses the otherwise idle
`$28000..$37fff` portion of the future main-image allocation. Its stop routine
runs before that image overwrites the slot. The separate boot stack and title/
intro images do not overlap it. The original Chip modules remain allocated.

The eight audited M.K. modules have these CPU-prefix sizes: intro 61,500 bytes,
end 17,468, each of the five level songs 7,228, and score 2,108. The copy counts
all 128 order entries and bounds the resulting pattern prefix before writing.
Native code still initializes sample data in Chip before the metadata copy.

The first candidate (`d-public-audio-finish-*`) matches the accepted D2/C
16,230 simulation hashes, 72 sound events, six terminal ranges, finish 16042,
exit 16231 and restart. `d-public-audio-sequence` covers title, seven intro
stages and race entry; all 31 race sample pointers remain Chip. Representative
normal rates are A500 8.5, Fast 020 16.7 and 060 28.1 fps. The 060 result is
below the preceding 28.3; this is recorded, not claimed as a speed improvement.

FX.ICE and fx2.ice have eleven/eight 8-byte descriptors. These use an existing
128-byte gap at public offset `$4e000`. Rebased relative offsets keep each of
the four native ADD.L consumers producing the original Chip sample pointer.
The native FX initialization remains responsible for flags and audio hardware.

Final candidate `d-public-audio-v3-build/RoadRash.slave` has SHA-256
`c4e013c4630bce3bbfc6858c51e0333f3444815c96635713ee7a53e85c5caff1`.
`d-public-audio-v3-finish-*` passes both cadences and the accepted D2 comparison.
`d-public-audio-v3-sequence-proof` verifies the entire 61,500-byte intro prefix
against its Chip original, both players' sample pointers, and each race FX2
sample address against its original descriptor. An earlier probe incorrectly
assumed eleven records for FX2; the corrected probe reads the native header.
`d-public-audio-v3-matrix-retry` records the representative normal matrix;
the initial Chip-only attempt timed out in the emulator debugger.

## D3 colour-conversion scratch

The original `$da7e..$11a7d` scratch has both CPU and DMA lifetimes. The
blitter uses it directly (for example `$b3cc6` writes it to BLTDPT, `$b3d06`
to BLTCPT and `$b3d3c` to BLTAPT); background pixels at `$f0de` also feed
BLTAPT at `$b2de2`. These graphics lifetimes retain Chip storage.

`public_recolor.s` separates the CPU-only colour-conversion lifetime: the
six calls of `$b1c6a` generate a 16 KiB table, and twelve references supply
it to the CPU recolouring routine `$b253c`. All eighteen explicit LEA sites
are checked before any is changed. The generated table now occupies public
`$61000..$64fff`; blitter and menu operands remain unchanged. Total optional
reservation is 404 KiB. No old Chip storage is reclaimed.

`d-public-recolor-finish-*` preserves the complete fixed/varying race results;
`d-public-recolor-matrix-tail` measures 8.5/16.7/28.1 fps on A500/Fast020/060.
Normal slave SHA-256: `b8068b883910c9ee34bbac836de48d44f0379cd4530937e0111f97e2ac5b413a`.

## D3 menu descriptions and joystick image

`public_menu.s` copies small-picture/shop and local-player descriptions into
two 128-byte slots at public `$4e080/$4e100`. Three typed renderer operands
are validated before use and updated only after complete copies. The local
player reader retains its native size addition through a corresponding base
adjustment. A count that exceeds a slot restores native readers. Pixels,
load/depack destinations and blitter scratch remain Chip.

The 2,224-byte joystick image is CPU-copied into portrait scratch before
rendering. Its stored source now uses `$4e180..$4ea2f`, within a reserved
3,584-byte gap, after native depacking. This hook preserves the native register
and CCR results and publishes the `$4e6` owner only after a bounded copy.
These changes do not increase the 404 KiB allocation.

`d-public-menu-final-finish-*` preserves all accepted race hashes/events,
finish/exit state and restart. `d-public-menu-final-proof` verifies both menu
descriptors byte-for-byte, joystick placement and size, and a 99-field trace
without DMA addressing their public slots, then reaches the race. The shop's
three-image set uses the same bounded first slot; its reader is statically
audited, not separately exercised by that menu trace.
Normal build SHA-256: `139996716e0fbc345040fbac60bfcef3cf86e6e22824442ae949d27d6ebd35ac`.

## Final residency audit and approved exception

`memory-assets.json` accounts for all 67 unpacked original assets, recording
names, sizes, hashes and consumer-based placement without including game data.
The inventory comprises four runtime executables, one unused original OS
bootstrap, 23 blitter image sets, twelve CPU-drawn portraits, one CPU-drawn
joystick image, one intro picture bundle, ten IFF screens, five backgrounds,
eight music modules and two sound-effect banks.

The low shared block retains fixed-address globals and interfaces. The
conservative reachable main-code audit finds 1,035 instruction sites referring
to 249 distinct absolute-short addresses in `$400..$467b`. This is a lower
bound, not a complete disassembly of every indirect path. An absolute-short
operand cannot represent the supported Fast RAM addresses. Moving this state
would require changing instruction sizes/control flow or adding execution
stubs, rather than adjusting relocation operands. The user explicitly approved
retaining these globals as a D3d exception on 2026-10-21. This exception is not
presented as a DMA requirement or as a completed instruction-rewriting project.
Future plan item [F6](performance-plan.md#f-cpu-work-reduction-all-cpus-the-68000-depends-on-it)
tracks investigating instruction rewriting or stubs and measuring whether moving
this CPU-only state is worthwhile. It does not reopen the completed D scope.

The same low region contains DMA structures and image storage. Vectors and
native shared loader entry `$4c98` retain their fixed interfaces. Loader copper
`$4cc4..$4d5f`, title/intro copper, main screens/copper/sprites, blitter sources,
masks/destinations and Paula samples remain Chip. The `$da7e` graphics scratch
and `$f0de` background have explicit blitter consumers; only their separable
CPU lifetimes move. `$467c/$467e` retain the blank-sprite alias.

Original load/depack storage remains allocated, including old executable and
asset copies. It is staging or compatibility storage, not a second writable
simulation state. No Chip memory is reclaimed. Native read/depack destinations
remain valid across reloads; public owners are published only after copies.
The 1 MiB Chip requirement is unchanged; optional public reservation is 404 KiB.
All changes remain behind the single default-off Enhanced framerate toggle.

## D3 encoded graphics and intro completion ordering

`public_iff.s` validates and copies each complete, even-sized FORM of at most
16 KiB into the colour-conversion scratch before the main CPU RLE decoder.
All ten inventoried screens fit (2,844–15,428 bytes). The colour table is
regenerated before each recolouring consumer and is not used by an interrupt;
these loader lifetimes do not overlap. Decoder register/CCR results are
preserved, and its returned A0 is translated back to the native source offset.
Unexpected formats or sizes use the original decoder input.

`public_intro_index.s` moves the complete 137,138-byte intro picture bundle,
including its eleven-entry index, into temporary public `$8000..$297b1`.
Boot music now uses `$30000..$3ffff`, leaving both regions clear of intro code,
loader and boot stack. Native main loading later overwrites these temporary
regions. The bundle is CPU palette/RLE input; decoded planes and copper remain
Chip. Its count and final picture endpoint are checked before copying.

The complete bundle exposed a native ordering bug: the two intro screen-clear
routines returned immediately after starting the blitter. The blitter could
overwrite faster CPU decoding and the following credits. Their enhanced exits
now wait for completion, preserving the original saved registers and CCR.
This is confined to intro loading/display preparation, not a race pacing wait.
The decoded-screen checkpoint comparison identifies the race: before the fix,
the native sample had already lost picture pixels; the public decode produced
the correct picture but later lost its credits. With the waits, both pictures
and credits display. The complete public bundle matches the unpacked file
byte-for-byte. `d-public-encoded-wait-sequence` covers all sampled intro stages,
race entry, music/FX pointers and boot guards. Its 152-field DMA audit finds no
DMA reads anywhere in the public allocation.

The intro-completion candidate has 27,904 bytes, SHA-256
`fd857ee83295968f81530d1de85d5b0cc544d636d432f75282d0ac4c62e444da`.

The intro completion fix changes only the tail helper starting at slave offset
`$6bd0` (and HUNK size words). All preceding runtime bytes are identical to
`d-public-encoded-build`, whose full accepted fixed/varying race comparison,
178-checkpoint native 68000 race/restart, all eleven normal machine cells,
040/060 MMU policies, keyboard/CD32, demos and off/native-Fast controls pass.
The final 040/060 data-cache-enabled checks also pass (`d-final-dcache-*`).
Race-end and restarted-race PNGs match the preceding menu build exactly.
Diagnostic-only failures from missing MMU policy defines and a long branch
in the enlarged test slave were corrected before the successful runs.

## Release validation

The final source additionally preserves the FX initializer's MOVE condition
codes from its original Chip pointer, even if a Fast allocation has its sign
bit set. `d-release-build/RoadRash.slave` is 27,908 bytes, SHA-256
`87df0c4f3883412f5dfc8e426548217ff856e25db19a647c9553cb2d07e33ac5`.

`d-release-finish-{fixed,vary}` reproduces the accepted 16,230 hashes, 72 sound
events, all six terminal regions, finish 16042, exit 16231 and restart.
`d-release-native-race-public` matches the original controlled native race's
178 checkpoints, input tape, finish/exit and restart exactly. Final MMU, stack,
keyboard/CD32 and demo checks pass in `d-release-functional-*`.
The immediately preceding intro-completion build also passes 040/060 data-cache
emulation (`d-final-dcache-*`); the subsequent FX change preserves registers and
CCR and introduces no new memory/cache operation. Eight normal-build paired
steering injections (`d-final-visible-020`) retain the prior estimates
140/120/160/140/120/160/140/120 ms. These include gameplay response and capture
uncertainty; they are not an artificial presentation delay or host-display latency.

| Final normal configuration | Frames/s |
|---|---:|
| A500, 1 MiB Chip | 8.5 |
| Native 68000 with Fast RAM | 8.8 |
| Chip-only 020 | 12.5 |
| Fast 020 default / Cache | 16.7 |
| Fast 020 NoCache | 16.6 |
| 030 default / Cache | 25.0 |
| 040 default / Cache | 25.2 |
| 060 default / Cache | 28.5 |

Evidence: `d-release-matrix-tail` (eleven normal cells) and `d-encoded-extra-*`
(toggle-off controls and native-Fast normal build). Rates are emulator samples,
not hardware claims. The latest equal-layout priority matrix
`d-final-priority-matrix` retains native priority on 020/030: 020 16.7 versus
16.6 cleared (NoCache 16.6 versus 16.4), and 030 25.0 either way. Clearing wins
on 040 (25.2 versus 25.0) and 060 (28.5 versus 25.0). The final encoded-image
changes run during loading and leave race rendering and that policy unchanged.

`d-release-bus` records 99 race fields, with no DMA address in the 404 KiB public
allocation. Remaining CPU Chip bus records are: screens/staging 170,429; approved
fixed low interfaces/data 48,560; low graphics assets 27,891; graphics assets
24,792; graphics scratch/background 28,608; vectors 299. There are no sampled
CPU bus records in the old main image. These are bus-record counts, not CPU-time
percentages; cache hits and unexecuted paths are outside this sample.

Final public layout (all offsets relative to ExpMem):

| Offset range | Lifetime / purpose |
|---|---|
| `$00000..$04fff` | Main supervisor stack, guards and spacing |
| `$05000..$413eb` | Main image; earlier title/intro temporary storage |
| `$08000..$297b1` | Intro-only encoded picture bundle, before main load |
| `$30000..$3ffff` | Boot music prefix, stopped before main load |
| `$42000..$48fcf` | Loader CPU image and external-call stubs |
| `$49000..$4d01f` | Separate guarded boot stack |
| `$4e000..$4e057` | Sound-effect descriptors (maximum) |
| `$4e080..$4e17f` | Two menu-description slots |
| `$4e180..$4ef7f` | Bounded joystick-source slot |
| `$50000..$5bfff` | Twelve ordinary and three fixed image-description slots |
| `$5c000..$60fff` | Main music header/pattern slot |
| `$61000..$64fff` | Mutually exclusive colour-conversion / IFF input scratch |

The intro-only rows intentionally reuse the later main-image range. Gaps remain
reserved. Main and boot stack guards, native 68000 selection and Chip-only
fallback are covered by the recorded runs. Hardware cache/coherency validation
remains explicitly pending by agreement. Earlier sections retain intermediate
results and open-work notes as implementation history; this release section
and the approved exception describe the final D scope.


### Bootstrap loading-picture correction (2026-10-21)

The initial loading animation has a separate one-image SET at loader `$6cf0`
(90 × 25 pixels, pixel base `$6d00`). The two absolute operands at `$4906`
and `$4a84` must retain the original Chip header at `$6cf0`/`$6cf2`:
`$49ae` adds the SET base to its pixel offset, and `$4a82` passes that pointer
to the blitter. Relocating both operands had made the animation three colored
rectangles. They are now excluded from `public_loader_refs`, while their native
values remain covered by `public_loader_check`. Other loader CPU state still
relocates. The retained mixed descriptor/pixel block is DMA-owned storage.

The production build restores the motorcycle/“BUSY” image on cached 040/25
and 040 with MMU/data caches. Both descriptor operands are verified as Chip
addresses and the initialized pixel pointer is `$6d00`; both runs proceed into
a race. Evidence: `tmp/dev/tmp/loading-graphics-fixed3` and
`tmp/dev/tmp/loading-graphics-mmu-fixed` (including screenshots and pointer
records). No race rendering, simulation, or allocation size changes.
