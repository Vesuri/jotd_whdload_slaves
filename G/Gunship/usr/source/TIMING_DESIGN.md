# Hybrid timing implementation notes

The governing design is PERFORMANCE_PLAN.md section C, as revised in
f56356a and 522ad23. The world runs at three native ticks per second; the
player must respond and move at field rate. Weapons launch at a world tick.
No field-rate integrator has been written.

## Implementation status

`timing-clock.i` and `timing-history.i` are standalone 68000-compatible
cores, not yet included in the slave. They do not change game behaviour.
C2 and C3 remain incomplete until the native adapters and lifecycle handling
are installed and tested.

The clock consumes consecutive unsigned field stamps. Each accepted field
adds three units; a world deadline consumes 50 or 60 units. PAL deadlines
therefore follow 17, 17, 16 fields; NTSC deadlines follow 20 fields.
The coordinator must run the world at each deadline before consuming the
next record. Display timing, not CPU type, selects the frequency.
Duplicate or missing stamps latch a fault. Pausing and explicit rebasing
discard partial phase with accounting; a slow render is not a rebase.

The history has 128 slots of 32 bytes. An interrupt producer copies the
complete record before publishing its word cursor. A foreground consumer
copies into private storage before releasing a slot. Full rings preserve
unread data, latch a fault and count rejected publications. Recovery must
exclude the producer and rebase the clock and history together.
The coordinator must check faults before using the copied input: a producer
can interrupt after the consumer's final fault check.

Record fields are declared in `timing-history.i`. They retain native filtered
direction, held buttons, relative accumulators, raw relative deltas, edge
mask, mode and a private command sequence. This is a storage contract; native
sampling, delta accumulation and command-sequence production are not installed.
Lifecycle calls require producer exclusion. The interrupt adapter must preserve
the interrupted registers and CCR; these cores return their result in d0/CCR.

## Native input audit (C3d)

Offsets below refer to the relocated original code hunk, not host addresses.

* The VBL server at +00F14 counts active-screen fields at +00F52. Its
  +04B48 callback reaches the fire latch before the current field's
  joystick/mouse finalisation at +01068. Preserve this phase relationship
  explicitly when recording edges.
* Relative mouse events enter +00FC0 and accumulate signed values at
  hunk 2 +002A/+002C. VBL smoothing precedes +01068, which converts these
  accumulators into directional controls. The tick reads the low bytes of
  the resulting long controls at hunk 2 +0008/+000C via +053F2.
  Raw deltas and these filtered directions are different quantities;
  consuming history must not apply the native filter twice.
* +04DC6 derives rising button edges from held state and counts them.
  +04E3C consumes the native latches. A field-history adapter must retain
  edges while handing each interval to the world only once.
* Keyboard production at +03488 uses a ten-entry shifting FIFO. +034E8
  removes the first word and shifts the remainder. Its count is not a
  monotonic cursor. The history's command sequence therefore needs a
  separate producer counter and an explicit mapping to retained commands;
  it must not reinterpret the native count as a cursor.
* The tick's recording/replay path at +05462 is separate from this FIFO.
  Native replay semantics need their own adapter test.

## Verification

The ignored development harness assembles both includes into a standalone
68000 hunk and executes their real instructions with Unicorn.
`tmp/dev/tools/test_timing_cores.py` exercised 112,781 calls: PAL/NTSC
deadlines over two minutes, field and cursor wrap, invalid configuration,
gaps, pause/rebase accounting, full-ring preservation and random FIFO
traffic. Composition tests consuming 600 fields in render batches of
1, 3, 10 and 25 produced identical field order and world deadlines.
Non-result registers and stack/return behaviour were checked.

These are sequential core tests, not interrupt-preemption tests or live
flight evidence. Native hooks, command retention, actual display-rate
detection, bounded catch-up, modal boundaries and CPU timing remain to test.
The player inventory is recorded separately in PLAYER_STATE_INVENTORY.md.
