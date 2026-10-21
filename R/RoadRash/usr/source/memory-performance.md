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
