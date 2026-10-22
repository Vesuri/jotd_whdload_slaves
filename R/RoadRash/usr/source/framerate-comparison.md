# In-game framerate comparison (2026-10-22)

The current 3.0b production slave was measured with Enhanced framerate disabled
(`CUSTOM2=0`) and enabled (`CUSTOM2=1`). Both sides include the unconditional
visibility and hill-projection fixes. This is an option-off/on comparison, not a
comparison against the historical 2.0 binary.

| Platform | CPU | Memory | Off fps | On fps | Gain |
|---|---|---|---:|---:|---:|
| A500, expanded | 68000, 7.09 MHz | 1 MiB Chip + 1.5 MiB Slow | 8.5 | 8.5 | 0% |
| A1200 | 68020, 14.19 MHz | 2 MiB Chip | 16.5 | 16.5 | 0% |
| A1200 + Fast | 68020, 14.19 MHz | 2 MiB Chip + 8 MiB Fast | 16.5 | 18.6 | 13% |
| A1200-030 | 68030, 50 MHz | 2 MiB Chip + 8 MiB Fast | 16.6 | 39.6 | 139% |
| A1200-040 | 68040, 25 MHz | 2 MiB Chip + 8 MiB Fast | 22.4 | 49.6 | 121% |

These are emulator measurements for a specific ten-second race window, not
whole-race averages, minimum rates, or physical accelerator guarantees. The
040 approaches the 50 Hz PAL presentation limit. The A500 without Fast RAM and
Chip-only A1200 retain their native paths, so toggling the option does not
improve their rates. The tested A500 is expanded to meet the slave/loader's
memory needs; it is not a stock 512 KiB machine.

## Method

- Normal, uninstrumented packaged slave, 39,228 bytes, SHA-256
  `55f24917ce843bddef178283acc006c09183173b5adf4998bb8c4d3cb51a6a05`.
- Sierra Nevada, level 1, default rider/bike. Route through the front end, settle
  at race field 100, then hold acceleration without steering through field 600.
  This gives identical input durations, not identical rendered scenes or
  simulation trajectories between modes.
- Count completed render frames through the native three-record rotation at
  `$a726e`, sampled every two PAL fields. At most two frames can complete in
  that interval under vsync, so the modulo-three counter is unambiguous. The
  established diagnostic harness previously cross-checked this counter against
  explicit completion instrumentation. FPS = completed frames / 10 seconds;
  the measurement resolution is 0.1 fps. No diagnostic game code is included.
- Fresh boot for every cell; two runs per mode/platform. All ten pairs reproduce
  their frame counts exactly: 85/85, 165/165, 165/186, 166/396 and 224/496
  (off/on, in table order).
- `PRELOAD Cache` requested in every cell. Cache handling remains the slave's
  normal mode-dependent behavior. Emulator CPU data-cache support is enabled
  for 030/040; the 020 has only an instruction cache. These settings differ from
  older default-cache or data-cache-disabled figures in the release report;
  do not combine those figures into a new off/on comparison.
- PAL, JIT disabled, CPU and memory cycle timing enabled. 030 uses the EC030
  selector; 040 uses the no-MMU selector, both with explicit CPU frequencies.
  MMU translation is disabled for this timing comparison. These are controlled
  timing configurations, not the shared interactive MMU-enabled presets.
- Private passive-read FS-UAE SHA-256
  `e0b2532ace1de7dd4d66d811488ec67ea7080b9991ee57e7190d8e31483f99cc`.
  Warp affects host execution duration, not the emulated PAL-field denominator.
  Host joystick input is disabled. Each run retains its effective configuration,
  tested slave, state snapshots, screenshots and frame count.

## Local reproduction and evidence

The ignored project harness contains `tmp/dev/tools/performance_compare.py`.
Run it from the worktree with `python3 tmp/dev/tools/performance_compare.py`.
It uses the exact slave from `tmp/dev/tmp/release-3.0b-visual-final/`, the existing
`matrix_a.py` machine configurations, and `public_invoke_d.py check_a.py --normal`
for the read-only relocated-memory view and measurement. Completed results are
reused; choose a fresh output directory for another independent batch.

Raw results: `tmp/dev/tmp/performance-comparison-3.0b/matrix.json`, plus the
`<cell>-custom2-<0|1>-r<1|2>/result.json` files. These local files contain no
changes to the game assets or installed interactive game. Hardware validation
remains separate from these emulator results.
