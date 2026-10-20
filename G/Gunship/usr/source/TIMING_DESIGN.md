# Hybrid timing implementation notes

The governing design is PERFORMANCE_PLAN.md section C, as revised in
f56356a and 522ad23. The world runs at three native ticks per second; the
player must respond and move at field rate. Weapons launch at a world tick.
No field-rate integrator has been written.

## Implementation status

`timing-clock.i` and `timing-history.i` are 68000-compatible cores.
The clock is still standalone. The history now has native producer hooks in
`timing-input.i`, installed only in builds with both VERIFY and TIMING_INPUT
defined, CUSTOM1=1 and CUSTOM2 nonzero, for the 0658 executable.
The boolean CUSTOM1 option **Enhanced framerate** gates all added framerate
patches and defaults off. The original slave's cache policy and compatibility
fixes remain baseline behaviour. Future scheduler/player/prediction and
render optimizations must share this gate.
C2 and C3 remain incomplete: the foreground player/world consumer, command
effect classification, and production lifecycle handling are not installed.
`timing-control-targets.i` implements standalone immediate command targets
and their common yaw tail; it is not included in a gameplay build yet.
`timing-presentation.i` likewise provides a standalone read-only camera and
instrument builder, with the native pitch clamp factored into a separate
player operation. Native-loop installation and gauge slew remain pending.
`timing-motion-preview.i` prepares and executes a native arithmetic clone
on a separate player record, excluding random/contact world effects.
It is also standalone; it does not yet scale or commit player motion.
`timing-fraction.i` supplies tested signed rational increments for that
future step. It does not select field-specific equations or coefficients.
`timing-motion-stages.i` exposes the native preview in ordered slices so
scaled rates can feed later displacement rather than scaling only the
final candidate pose. The slices themselves still use native increments.

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
mask, mode and a private command sequence. Diagnostic native hooks now supply
these values: raw deltas are accumulated before native scaling, filtered
directions are copied after the native sampler, and the command counter
advances only on accepted native FIFO insertions.
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

## Native producer diagnostics

The installer validates all four displaced instruction sites before patching
any of them: the VBL sampler call at +00FA0, raw mouse read at +00FC6,
accepted command insertion at +034C8, and fire sampler at +04DC6.
The normal sampler, native FIFO and native fire latches continue to operate.
No game consumer reads the new history yet.

The diagnostic marker `GSIH0001` publishes the code/input hunk addresses,
history and scratch-record addresses, accepted-command sequence, raw-delta
accumulators, fire edges, arm request and native sampler address. An extension
at +44 publishes the retained-command queue address.
Raw key 7F hex, which has no dedicated native action, requests a fresh capture at the next active VBL.
This diagnostic-only trigger avoids debugger memory writes. The VBL resets
the ring with its current field minus one as the epoch, then publishes the
current field. This is a test fixture, not the production modal/rebase policy.

Raw deltas accumulate in signed longs. A value that cannot fit the record's
signed word faults the active history instead of publishing a truncated
delta. Fire edges intentionally describe the preceding field's held state;
the record's held buttons describe the newly sampled state. This matches
the original callback-before-sampler order.

`timing-commands.i` retains up to 128 accepted native key/modifier words, each
with its 32-bit sequence. Player and world readers have independent cursors.
Both inspect each command, but the eventual dispatcher must apply only that
reader's owned effects. A slot cannot be reused until both readers pass it.
`commands_pop` takes a field record's sequence cutoff and never returns a
later command; cutoffs and sequences may wrap. Overflow preserves unread
payloads and faults the interval instead of silently losing an input.

The native command hook excludes interrupts across queue publication and
the field-cutoff update. It preserves the displaced instructions' registers
and flags, including X, without requiring a privileged SR read in the input
task. The diagnostic arm key initializes the command epoch before requesting
the next VBL's field-history reset. It is not retained as a command to replay.
Native decoding still runs the shared yaw tail for this key; it is not a
strict state-preserving no-op (see the command audit below).
Subsequent key words survive native FIFO consumption.
The VBL propagates command loss into the field-history fault. The eventual
coordinator must also check command faults directly before committing work,
including losses after a field record was published.

Production pause/rebase must exclude producer and both consumers, discard
unread fields and command intervals together, and account for losses.
`commands_rebase` counts retained slots discarded (the larger unread count),
preserving lifetime loss/discard diagnostics. Native FIFO overflow remains
the native input acceptance policy; only accepted insertions are retained.

## Native command ownership audit

Command words below are hexadecimal, including modifiers. The native decoder
at +04ED4 compares full words, so a dispatcher must not strip modifiers.
This is an ownership inventory, not an installed command dispatcher.

| Command | Native action / boundary | Owner |
|---|---|---|
| 4C/4D, 4E, 4F | Set view byte 1A to 0, +32, -32 | Player/presentation |
| 50/5A, 51/5B, 52/5C, 53/5D | Add +4, +1, -1, -4 to collective 39; clamp 0..42 | Player control target |
| 38, 39, 3A | Decrement, clear, increment yaw byte 3F | Player control target |
| 01, 02 | Toggle engine bits 2/3 in byte 42, conditional on reserves and damage; notify and update instrument state | World |
| 03 | Toggle bit 4 in byte 42; when the old bit was set, also clear collective 39; notify | Mixed; ordered reset must reach player |
| 04..07 | Set weapon byte 41 and call +07EEE | World |
| 09, 0B | Damage-gated resource check at +07C1C; set countermeasure bytes 44/45 to 36; notifications | World |
| 08, 0A | Damage-gated toggles of bits 1/0 in byte 42; external indicator writes and notifications | World |
| 0804..0806 | Clear instrument bytes, notify and call +07C38 | World; callback audit pending |
| 45, 0833 | Set flight-end byte 18, with an exceptional return path | Lifecycle/world |
| 0C | Toggle byte 51, save/restore a display word and rebuild display | Presentation; callback audit pending |
| 40, 1C/41, 37/21/22, 34, 42, 46 | Call UI/navigation/modal routines or write their request flags | Lifecycle/UI; callback audit pending |

The common tail at +052CC clamps yaw to -4..4. It then computes the
byte-width negative absolute value of coarse speed 50 and compares it
**unsigned** with 15 at +052F0. For every nonzero signed-byte speed this
clears yaw at +052F6; speed zero retains the clamped value. Preserve the
actual byte arithmetic rather than substituting an apparent speed threshold.
This tail runs for ordinary continuing commands, including an unknown key.
Exceptional flight-end/modal exits need their own lifecycle handling.

`tmp/dev/tools/audit_player_commands_c.py` runs the original decoder, without
stubs, for all 15 immediate control words plus 7F and their 0800-modified
variants. All 86,688 combinations of legal collective/yaw targets and seven
signed coarse speeds match expected complete player records. Memory-write
hooks observe only view 1A, collective 39 and yaw 3F outside the stack.
Evidence: `tmp/dev/tmp/c/player-command-audit.json`.

Ownership must therefore be applied to effects, not just whole commands:
the player reader must apply the shared yaw effect exactly once at the
command's field, even when the primary action belongs to the world. The
world reader must not replay that tail against a later player pose.
The mixed 03 command needs an explicit ordered reset protocol: deferring
its collective clear and applying it after newer field commands would
reverse their order. This remains an integration obligation; the two queue
cursors alone do not solve it. Engine/resource/UI callbacks are not covered
by the immediate-control fixture.

### Field-owned command helper

`control_target_command` takes the complete command word in d0 and the
native player record in a0. It applies only the 15 view/collective/yaw
primary actions above, returning 1 when handled and 0 otherwise. Unknown
words leave the record untouched. It preserves d1-d7/a0-a6.
Collective arithmetic retains native byte wrapping before saturation.
Yaw increment/decrement similarly retains byte width.

`control_target_tail` takes the player record in a0, preserves all data
and address registers, and applies the native common yaw clamp/speed reset.
Keeping it separate lets the eventual dispatcher run it once for continuing
commands whose primary action is world-owned. Neither helper calls game
code, consumes command cursors, changes the world clock or implements
fractional motion. CCR is not part of either helper's return contract.
They are standalone 68000 code and must be reached only through a
CUSTOM1-gated installer when the native hand-off is ready.

`tmp/dev/tools/test_control_targets_c.py` compares assembled helper output
with the original decoder in 90,528 cases, including every byte value for
collective/yaw to exercise wrapping. Complete 86-byte records match.
It also checks all 65,536 command words: only the 15 owned primary actions
are accepted, and every rejected word leaves the record unchanged.
Each call checks preserved registers and stack/return behaviour.
Evidence: `tmp/dev/tmp/c/control-target-tests.json`.

## Read-only presentation builder

`timing-presentation.i` separates the native +056D8..+05830 work into two
operations. `player_pitch_clamp` takes the player record in a0 and performs
the exact native byte clamp. Its lower-bound branch uses BMI after byte
subtraction, including the native overflow behaviour for out-of-range
positive bytes. It must be scheduled explicitly relative to controls and
recoil in the player step; calling it from rendering would reintroduce
frame-dependent authoritative writes.

`presentation_build` reads that player state and writes only instrument
targets and the camera vector. Inputs are a0 = player, a1 = the 16-byte
instrument block (native hunk 6 +157D), a2 = the 12-byte camera vector,
and a3 = the native interpolation table (hunk 4 +01C8).
It preserves all data/address registers; CCR is unspecified. Because the
native instrument block starts at an odd address, a1 must have the same
parity so its word at offset 7 is aligned. Other pointer inputs are even.
The builder preserves untouched instrument bytes and applies the seven-byte
damage override exactly. It reproduces the vertical gauge's table
interpolation and rounding, and byte-width angle wrapping/negation.

This builds **target values**, not the per-buffer gauge animation. The
elapsed-field slew and native installation still belong to C4g; this
helper alone does not complete that item. When installed, it must share
the CUSTOM1 gate and use the actual native table and output addresses.

`tmp/dev/tools/test_presentation_c.py` compares the original native builder
against explicit clamp followed by presentation build in 65,536 cases.
Every pitch/vertical-rate byte pair is covered, with random remaining
player bytes and retained instrument values. Complete player records,
all 16 instrument bytes and all 12 camera bytes match. Alternate output
addresses with guard bytes catch fixed-address or out-of-bounds stores.
The fixture verifies register preservation and 256 repeated builds with
unchanged player state and outputs.
Evidence: `tmp/dev/tmp/c/presentation-tests.json`.

## Native motion preview boundary

`timing-motion-preview.i` reuses the 0658 flight routine rather than
translating its arithmetic. `motion_preview_prepare` takes the validated
code-hunk base in a0 and a separate, even, 1,054-byte destination in a1.
It copies +0937C..+0979A with the embedded RPM table at the same relative
position. All six sine calls continue to use the original native helper
and table. Only two branch instructions are changed in the copy:

* +09474 jumps to +09492, bypassing the random damage-heading impulse.
* +095A0 jumps to +09636, bypassing ground classification, notifications,
  flight-end state, crash state and the speed/attitude/vertical-rate resets.

The native altitude clamp and arithmetic before/after these world-owned
blocks still execute. The routine produces a deterministic motion candidate,
including derived quantities, without advancing gameplay RNG. It is not a
full native tick: the omitted impulses/contact consequences must be
evaluated at the world boundary, with their native ordering accounted for
in the eventual h=1 gate. In particular, an airborne-to-ground transition
must not be inferred solely from the final candidate height; the pre-step
airborne state remains an explicit hand-off requirement.

Preparation checks both patch boundaries, routine entry/return, and all
eight absolute call instructions/targets before writing the destination.
These checks supplement, not replace, the caller's 0658 version validation.
It returns 0 on success or -1 on mismatch and preserves non-result
registers. Allocation bounds and non-overlap are caller contracts.
**The installer must flush instruction caches after preparation and before
executing the clone.** No running game code is patched by these helpers.

`motion_preview` takes the authoritative player record in a0, a distinct
86-byte result in a1 and the prepared clone in a2. It copies the input,
executes native arithmetic with a5 pointing to the result, and preserves
all data/address registers (CCR unspecified). The caller owns the scratch
record and must not overlap it with the source or code. This is a whole
native increment candidate, not the fractional field-rate integrator.
Neither helper is included in normal/diagnostic gameplay builds yet.
Any future installation must use the master CUSTOM1 gate.

`tmp/dev/tools/test_motion_preview_c.py` checks 384 airborne cases against
the unmodified original routine with random-impulse damage bits clear.
Another 3,712 low-altitude cases compare against original code with the
same two world blocks skipped by execution hooks, reaching the contact
boundary 552 times. This second set tests extraction/isolation, not native
contact-result equivalence. All 4,096 complete result records match;
memory-write hooks observe no writes outside the result and stack, and the
authoritative input remains unchanged. Registers and output guards pass.
Twenty-one malformed boundary/call fixtures fail before destination writes.
Evidence: `tmp/dev/tmp/c/motion-preview-tests.json`.

### Ordered motion slices

`timing-motion-stages.i` prepares seven immutable copies of the validated
preview, each returning at a distinct native boundary. They require 7,378
bytes of code storage plus a 12-byte d0/d1/d2 term record. Their native
relative branches and embedded table remain intact; there is no code
rewriting during a field step. Preparation calls the preview validator
before writing and requires the same post-preparation cache flush.

| Stage | Native span | Output / dependency |
|---|---|---|
| 0 | +0937C..+09492 | Power, heading and track; random impulse excluded |
| 1 | +09492..+09576 | Lift, target speed and native vertical response; d0.w is the signed vertical target, d1.w the old vertical rate |
| 2 | +09576..+09636 | Height from the rate currently in the record; contact block excluded; d2 low byte retains the pre-integration airborne test |
| 3 | +09636..+09664 | Corrected speed error in d0.w and signed one-unit slew in d1.w; no player writes |
| 4 | +09664..+09672 | Native rounded speed approach plus slew |
| 5 | +09672..+096FE | Coarse speed, horizontal displacement, coordinate clamp and wind |
| 6 | +096FE..+09798 | RPM target and powered/coasting response |

`motion_stage` takes stage number in d0, the private player record in a0,
prepared code in a1, and terms in a2. It updates the private record and
captures d0/d1/d2 at return. It returns d0=0 on success or -1 for an invalid
stage without writes; non-result registers are preserved. Initialize terms
to zero and execute stages in order unless explicitly satisfying the listed
dependencies. Stage 5 loads speed from the record, so a caller's adjusted
speed replaces the earlier whole-tick register result.

This provides the necessary update-order boundary for the field integrator:
replace the stage-1 vertical response before stage 2, and use stage 3's
raw error/slew to form the field speed before stage 5. It does not yet
implement those replacements. Angular response, position/height saturation
and separate wind scaling still require their native operation ordering;
blindly scaling a slice's final clamped position difference is insufficient.
The extra copy/storage and call cost must be included in C4f's price.

`tmp/dev/tools/test_motion_stages_c.py` executes all seven slices in 4,096
airborne/low-altitude cases (28,672 stage calls). Complete player records
match the whole deterministic preview. It checks the exposed vertical
target/old-rate and forward error/slew against the native response equations.
Four invalid stage numbers preserve record, terms and prepared code.
Forty additional cases deliberately replace speed between slices while
leaving stale register terms; horizontal outputs match an independently
entered native coordinate block using the new speed. The reference uses
its own returning copy because stopping inside an already-translated
whole-routine block was unreliable in the CPU test harness.
The separate preview tests remain the evidence for isolation from world
RNG/contact effects; this is not a full C4e gate.
Evidence: `tmp/dev/tmp/c/motion-stages-tests.json`.

## Fractional arithmetic contract

`timing-fraction.i` provides `fraction_scale`, a standalone 68000 operation.
Inputs are a0 = a signed long remainder, d0 = a sign-extended native word
increment, d1 = numerator and d2 = denominator. Valid inputs satisfy
`0 <= numerator <= denominator <= 32767`, denominator nonzero, and
`-denominator < remainder < denominator`. It computes
`total = increment * numerator + remainder`, returns the quotient truncated
toward zero in d0, and retains the signed division remainder at a0.
d1 returns 0 for success or -1 for invalid input; invalid input returns
d0=0 and leaves state untouched. d2-d7/a0-a6 are preserved.

Rates can therefore use exact 3/50 or 3/60 ratios without approximating
the field duration in binary fixed point. The denominator belongs to the
remainder's unit and must not change without reset/conversion. Each
independent integrated quantity needs its own state; one shared remainder
would couple unrelated movements. With numerator equal to denominator and
an initially zero remainder, the native integer increment is reproduced
exactly. Nonzero residuals retain their mathematical effect; the h=1 player
fixture must initialize shadow state consistently with its native reference.

This primitive does **not** make the motion preview directly integrable:
derived targets/power/coarse speed must be recomputed, not scaled as rates;
angular differences need native modular interpretation; response terms
need their own r^h conversion; native speed's signed slew is separate from
its one-sixteenth approach. Saturation/ground resets must account for or
clear the corresponding residual instead of accumulating motion against a
stop. The eventual lifecycle manifest must enumerate every allocated
fraction and its initialization/rebase/impulse reset point. No persistent
player shadow state is allocated by this helper.

`tmp/dev/tools/test_fraction_c.py` passes 36,391 assembled calls against
independent integer division. Coverage includes signed-word extremes,
denominator/numerator/remainder boundaries, invalid inputs without writes,
and register preservation. Constant positive and negative rates accumulate
exactly three native increments over 50 PAL or 60 NTSC fields. Mixed-sign
600-field tapes processed in batches of 1/3/10/25 produce identical output
and residual, with exact total accounting. This proves the arithmetic
component, not the complete player-step equivalence gate.
Evidence: `tmp/dev/tmp/c/fraction-tests.json`.

## Foreground coordinator

`timing-scheduler.i` composes the clock, field history and retained-command
queue. It is assembled/tested separately, not installed into the native main
loop. Its caller must supply the actual player step, command dispatch and
native world tick; acknowledgements are not substitutes for those operations.

`scheduler_begin` snapshots the available backlog with a field budget
(1..128) and world budget (1..8). Newly published fields belong to the next
batch. `scheduler_next` delivers one private field record and advances the
clock. It then refuses further input until `scheduler_player_done`. At a
deadline that acknowledgement requires a world tick, and the coordinator
refuses later fields until `scheduler_world_done`.

The delivered command cutoff is available to both command readers. Held
buttons track the latest consumed field; rising-edge bits accumulate until
world completion, preserving a press released before the deadline. The native
tick collapses its fire counters to nonzero flags, so the interval retains
presence rather than inventing multiple launches in one tick.

The coordinator stops **before** consuming a field that would exceed the
world budget. Exhausting a capped field snapshot also reports a bound.
Neither condition silently drops time or permits a fresh budget over the
unfinished batch. Production recovery must explicitly account for/discard
excess history and rebase the clock, history and command queue together,
then call `scheduler_rebase` with producers excluded.

Upstream inactive/fault states latch the coordinator until that explicit
recovery. Completion acknowledgements count already-applied work even if a
producer fault arrived during it. Clock counters describe accepted fields
and deadlines; coordinator counters describe completed player/world steps.
Recovery reporting must include their differences as well as unread history,
lost publications and discarded clock phase.

The native main-loop adapter, actual display-frequency selection, production
catch-up limits and modal lifecycle hooks remain pending. Any installation
must remain behind the CUSTOM1 Enhanced framerate gate.

## Verification

The ignored development harness assembles both includes into a standalone
68000 hunk and executes their real instructions with Unicorn.
`tmp/dev/tools/test_timing_cores.py` exercised 112,781 calls: PAL/NTSC
deadlines over two minutes, field and cursor wrap, invalid configuration,
gaps, pause/rebase accounting, full-ring preservation and random FIFO
traffic. Composition tests consuming 600 fields in render batches of
1, 3, 10 and 25 produced identical field order and world deadlines.
Non-result registers and stack/return behaviour were checked.

`tmp/dev/tools/test_history_preemption.py` additionally interrupts the real
consumer at every instruction boundary, runs the producer, restores the
interrupted CPU state and resumes the consumer. All 120 cases pass at
occupancies 0, 1, 127 and 128: no torn record, premature slot release or
overwrite of unread data. Two full-ring interleavings return a valid copied
record alongside a newly latched fault, confirming that the coordinator
must not treat a successful pop as proof of an unfaulted interval.

`tmp/dev/tools/test_timing_input.py` passes 457 assembled adapter cases.
It compares mouse, keyboard and fire hook register/CCR results with their
displaced native instructions, checks sampler-result preservation, complete
record payloads, signed-delta overflow, and diagnostic arm/recovery.
It also verifies the master gate and the version-17 slave header's boolean
configuration string. With CUSTOM1 off the input installer leaves all state
untouched and never calls the patch service; with it on, validated installation
reaches that service. The blitter suite passes 182 cases, including off/on
dispatch against both PAL and NTSC executables. Live diagnostic captures below
predate the master gate; repeating them now requires CUSTOM1=1.

Live FS-UAE captures on 68000, 68020 and 68060 each published 47 consecutive
active-field records with no loss/fault. All retained the injected raw delta
sum (8, -12), accepted-command sequences 4..6, directional changes, held fire
and its rising edge. The edge appeared one field after the held-button rise,
as in the native code. Retained evidence is under `tmp/dev/tmp/c/input-live-*`.
The first 68000 attempt did not reach the instrumented game screen; after
reported mouse interference, its retry passed.

Native relative smoothing alternates zero and minus one at rest because its
zero-decay case forces a subtraction of one. Captures starting on opposite
field parity therefore differ in those accumulators and can differ by one
field at a directional threshold. These captures verify faithful sampling;
they are not identical-initial-state world or integrator comparisons.

A subsequent live 68020 capture with CUSTOM1=1 retained commands 5 and 6 as
native words 004C and 0050 (up-arrow and F1), while neither diagnostic reader
had advanced. Its 47 field records retained the same sequence cutoffs and
the injected mouse/button events. Evidence: `tmp/dev/tmp/c/commands-live-020`.
The assembled adapter's 457 ABI/header/gate checks also pass with retention.
`tmp/dev/tools/test_timing_commands.py` passes 30,511 assembled calls with
independently delayed player/world readers, exact key/modifier payloads,
field cutoffs, 16-bit cursor and 32-bit sequence wrap, full-ring preservation,
invalid roles, pause and loss-accounted rebase. Normal and existing VERIFY
build hashes are unchanged by this diagnostic command-retention change.

`tmp/dev/tools/test_timing_scheduler.py` passes 12,999 assembled calls.
PAL/NTSC tapes with batches of 1, 10 and 25 fields produce the same ordered
player fields and world deadlines, including field-stamp wrap. Tests also
cover mandatory acknowledgements, snapshot isolation from later publications,
field/world budgets, all upstream fault/inactive sources, explicit coordinated
rebase, completion accounting after faults, and a short trigger press retained
until its world deadline. These tests do not execute the native player or world.

Command effect classification, actual display-rate detection, bounded catch-up,
modal boundaries, input replay and CPU cost remain to test.
The player inventory is recorded separately in PLAYER_STATE_INVENTORY.md.
