# Road Rash 3.0b (22.10.2026)

G1–G4 are complete. This beta retains the agreed emulator-only validation scope:
D1d physical 68040/68060 cache/coherency testing and F6a–F6d investigation of the
fixed-address globals remain future work. No distribution upload is part of G.

## Build and package

The AmigaXDev environment supplies vasm, WHDLoad includes, NDK includes, the LHa
compressor and `amigaxdev.release`. From this source directory:

```
make
make dist ORIGINAL=/path/to/original/RoadRash.lha OUT=/path/to/fresh/output
```

Paths with spaces are supported. `AMIGA_SHARE`, `VASM` and `LHA` are overridable.
`make clean` removes only the local built slave. `make dist` always assembles a
fresh normal build, checks the option/version/date and absence of diagnostics,
and refuses an existing output directory or an unrecognized original installer.
The accepted original is the version 2.0 installer, pinned by SHA-256 in
`package_release.py`. The default paths use the ignored development harness.

Output contains `RoadRash_v3.0b.lha`, the exact built `RoadRash.slave`, a SHA-256
member manifest, staging, and an independent extraction. The compressed archive
contains the original `RoadRashHD` drawer, not preinstalled game data. Original
manuals and icons are unchanged. Intentional changes are Install, Readme, the
slave and the source directory: the latter now contains all current assembly,
validation documentation and build/package tools; the obsolete 2002 `.asm` is
removed. No private fixtures, game assets, emulator or original disks are included.
Portable generic LH5/LH0 headers have a fixed release timestamp and no host owner
metadata. Integrity testing plus independent Lhasa extraction checks every file
against staging. Two builds from the same inputs produce identical archives.

## Templates and retained installation behavior

Based on the WHDLoad developer package's `Install Template/Xxx Install` files:

| Input | SHA-256 |
|---|---|
| Install | `a297dec9be45a05293a5768e2ae09d7be1f5fbf1fd8ebd49638214247ce84f37` |
| ReadMe | `a4c2d4271610864e6a8abdf8a4cd3d4ba50c0857fa8e8b274bd4bde0763f818b` |

The template's file-copy branch retains the 2.0 disk-label choices (`rr1` or
`Road Rash`), all files from disk 1's root, and all files from disk 2's `data`
directory on volume `roadrash`. Files install into `RoadRash/data`. The five
original RomIcon, NewIcon, OS3.5, Glow and Exoticon variants remain available;
Slave, PRELOAD, WHDLoad and stack settings are initialized by the template.
CUSTOM2 is not forced in any icon. Existing destination drawers or drawer icons
require explicit replacement; cancellation leaves them and saved games intact.

The ReadMe uses the template's requirements/features/history/contact structure,
retains the old history, credits, controls, password examples and ending hints,
and corrects the quit-key documentation to Help (the slave's existing `$5f`).
Only user-visible changes since 2.0 appear in the 3.0b history entry. Low-level
optimization details belong in the source documents, not the release changelog.

## Defaults and measurements

All performance enhancements remain behind the single default-off CUSTOM2
boolean, "Enhanced framerate". CUSTOM1 and CUSTOM keep their password meanings.
With the option enabled, the measured CPU/memory gates select the appropriate
implementation; there are no extra user-facing performance switches. In
particular, Chip-only 68000 remains native while Fast RAM 68000 benefits from
relocation/rendering improvements without changing simulation timing.

Normal production build, 500 PAL fields of throttle in the established first-race
scenario (emulator samples, not hardware guarantees or minimum frame rates):

| Machine | CUSTOM2=1 fps |
|---|---:|
| 68000, 1 MiB Chip + Slow | 8.5 |
| 68000 with Fast | 9.4 |
| 68020, Chip only | 12.5 |
| 68020 with Fast | 18.6 |
| 68030/50 with Fast | 39.4 |
| 68040/25 with Fast | 49.6 |
| 68060/50 with Fast | 49.6 |

The 1 MiB Chip A500 also measures 8.5 with CUSTOM2 off, confirming no enhancement
regression on that fallback. Option-off 020/040 boot and run at 12.5/22.6 fps.
Historical 2.0 measurements in the plan remain historical, not a claim that all
unconditional correctness fixes have zero cost. The final metadata-only `$VER`
addition leaves executable offsets unchanged; the exact packaged binary was
rechecked on 040 and A500 and produces the same throughput.

A later matched off/on comparison of the visual-fix build, with `PRELOAD Cache`
requested throughout, is recorded in [framerate-comparison.md](framerate-comparison.md).
It includes exact CPU/memory/cache settings and repeated measurements; the table
above retains its original release-validation settings.

## Release verification

- A4a: 399 applied throttle fields on 040, completed simulation boundaries:
  distance 2,400,287 versus B's 2,395,852, +0.185112%, inside ±1%. Full early
  trajectories and live-field boundaries remain diagnostics; tiny startup
  displacements are not claimed identical across different integration steps.
- A4b: fixed and varying render-cadence full races match all 16,230 simulation
  hashes and 72 sound events, terminal actor/rank state, finish at 16,042 and
  end time 16,231; both restart successfully. This retains the previously
  approved corrected handling baseline rather than asserting native RNG identity.
- A4c: settled front-end and race captures at fields 100, 500, 1000 and 2000
  show the corrected Chip-resident graphics; all 27 embedded pixel pointers
  remain in Chip RAM. The initial loading-picture fix is retained unchanged.
- B1: joystick steering recentres; keyboard and CD32 pause/resume stop and
  restart simulation correctly. Fast-stack guards pass.
- A separate visible-steering capture pair at field 300 on 040 first differs
  at field 305, retaining the earlier conservative 100 ms upper bound. This
  is measured total response, not an added delay or a claim of zero latency.
- 040 and 060 MMU/data-cache-enabled functional boots verify enabled translation,
  all 256 supervisor and 256 user BaseMem pages write-through, Fast code/stack
  copyback and intact stack guards. Physical cache testing remains D1d.
- Native Amiga Installer 43.3 executes both disk-label variants with each of
  the five original icon choices, copying disk-root and disk-data fixtures into
  destination paths containing spaces. A separate existing-install replacement
  removes the old drawer/icon; cancellation preserves the saved-game sentinel
  and old icon, with no new slave written. These are native file/tooltype tests
  with scripted answers and mounted synthetic disk volumes; physical floppy
  reads, image-device integrations and newer Installer icon previews are not
  claimed tested. The stock prompt expressions also pass structural validation.

Evidence is retained under ignored `tmp/dev/tmp/g-*`: `g-checks.json`,
`g-final-checks.json`, `g-exposure-comparison.json`, `g-final-finish-fixed/vary`,
`g-smoke-*`, `g-visible-result.json`, and `g-installer-native/result.json`.
The release directory has its own complete file/hash manifest. The Makefile's
normal build and harness normal build are byte-identical.

## Original visual fixes, 22 October follow-up

The same 3.0b version/date now includes stable distant/mirror rider visibility
and corrected hill projection in both CUSTOM2 modes. See [visual-fixes.md](visual-fixes.md)
for implementation, replay equivalence and unchanged measured throughput.
The updated installer is built under `tmp/dev/tmp/release-3.0b-visual-final/`;
its manifest records the exact source and slave hashes. Earlier archive hashes
in this document describe the preceding build.

## Interactive A1200-030 playtest, 22 October

The user played the current visual-fix build on the shared interactive
`a1200-030` emulator preset and reported a very positive result. This provides
user playtest confirmation alongside the automated comparisons; it does not
claim exhaustive defect coverage or physical-hardware validation.

The effective setup was a 50 MHz 68030 with 68030 MMU, 2 MiB Chip and 8 MiB
Fast RAM, emulator data-cache support enabled, and WHDLoad
`PRELOAD Cache CUSTOM2=1`. The normal 3.0b slave SHA-256 was
`55f24917ce843bddef178283acc006c09183173b5adf4998bb8c4d3cb51a6a05`.
The session's startup command, effective configuration and tested slave are
retained locally in `tmp/dev/tmp/play-030-20261022-100742/`.

No FPS measurement was taken during this interactive session. The repeated
39.6 fps 030 result in [framerate-comparison.md](framerate-comparison.md) comes
from the separate controlled, no-MMU benchmark. Physical cache/coherency
validation (D1d) and future fixed-address-global work (F6) remain outstanding.
