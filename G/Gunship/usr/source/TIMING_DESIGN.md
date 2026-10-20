# Hybrid timing implementation notes

The governing design is PERFORMANCE_PLAN.md section C, as revised in
f56356a and 522ad23. The world runs at three native ticks per second; the
player must respond and move at field rate. Weapons launch at a world tick.
The complete field-rate motion integrator and native hand-off are not written.
The deterministic stick-attitude component now has a standalone field step.

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
`timing-response.i` supplies fraction-aware quarter/eighth/sixteenth
approach responses using r^h field gains and exact native h=1 rounding.
`timing-flight-rates.i` connects vertical, forward and RPM responses to
the native stages, including additive slew/coasting and retained fractions.
`timing-heading.i` replaces native stage 0's angle writes with coupled
field-rate heading/track updates and explicit world heading impulses.
`timing-movement.i` replaces height and horizontal displacement/wind,
retaining native quantization and boundary order while scaling by 3/rate.
`timing-motion-stages.i` exposes the native preview in ordered slices so
scaled rates can feed later displacement rather than scaling only the
final candidate pose. The slices themselves still use native increments.
`timing-attitude.i` consumes normalized stick directions at field rate,
retaining pitch/roll fractions and previous-field vertical input. It is
standalone, accepts externally supplied world impulses, and excludes RNG
generation and the separate HUD pitch clamp.

The clock consumes consecutive unsigned field stamps. Each accepted field
adds three units; a world deadline consumes 50 or 60 units. PAL deadlines
therefore follow 17, 17, 16 fields; NTSC deadlines follow 20 fields.
The coordinator must run the world at each deadline before consuming the
next record. Display timing, not CPU type, selects the frequency.
Duplicate or missing stamps latch a fault. Pausing and explicit rebasing
discard partial phase with accounting; a slow render is not a rebase.

The history has 128 slots of 40 bytes (5,140 bytes including the header). An interrupt producer copies the
complete record before publishing its word cursor. A foreground consumer
copies into private storage before releasing a slot. Full rings preserve
unread data, latch a fault and count rejected publications. Recovery must
exclude the producer and rebase the clock and history together.
The coordinator must check faults before using the copied input: a producer
can interrupt after the consumer's final fault check.

Record fields are declared in `timing-history.i`. They retain native filtered
direction, held buttons, relative accumulators, raw relative deltas, edge
mask, mode, a private command sequence, and the native RNG input-event
timestamp (seconds and microseconds). Diagnostic native hooks now supply
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

`timing-controls.i` now converts a copied history record into the
10-byte player-step packet. `controls_from_history(a0=record,a1=packet)`
sign-extends only the low byte of TR_X/TR_Y, exactly as the native
+0544A consumer does. It accepts -1/0/+1 and rejects other direction
bytes before any output write. Upper longword bits are intentionally
ignored: the sampler can use a word-sized move for +1 after a long-sized
-1, so validating the entire long as canonical -1/0/+1 would reject
valid native inputs.

The adapter does not consume raw mouse deltas or relative accumulators;
the recorded directions already include the native filter. It zeroes all
three world-impulse words on success to prevent a reused packet from
replaying an old impulse. The world owner may supply eligible impulses
after decoding. Buttons/edges remain the scheduler/world consumer's
responsibility. This helper does not advance a history cursor or
acknowledge a field; its native scheduler wiring and replay-mode path
remain pending.

Thirty-six native comparisons cover all x/y direction pairs and four
upper-bit patterns, including FFFF0001. Eight invalid-direction cases
reject without writes. Randomized record metadata, output guards,
register/stack preservation and zeroed impulse words are checked.
Evidence: `tmp/dev/tools/test_controls_c.py`,
`tmp/dev/tmp/c/controls-tests.json`.

The installer validates all four displaced instruction sites before patching
any of them: the VBL sampler call at +00FA0, raw mouse read at +00FC6,
accepted command insertion at +034C8, and fire sampler at +04DC6.
The normal sampler, native FIFO and native fire latches continue to operate.
No game consumer reads the new history yet.

The diagnostic marker `GSIH0002` (40-byte records; previously `GSIH0001`
with 32-byte records) publishes the code/input hunk addresses,
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

## Command inspection and acknowledgement

The retained queue now exposes `commands_peek` with the same arguments and
field-cutoff semantics as `commands_pop`, but without advancing either reader.
`commands_ack` takes queue a0, that reader's private eight-byte record a1
and role d1 (0 player, 1 world). It compares both longs with the current head
before advancing only that cursor. Returns are 1 acknowledged, 0 empty or
inactive, -1 fault, -2 invalid role and -3 stale/modified record. All non-result
registers are preserved. Existing `commands_pop` retains its original API.

This permits classification before consumption: an unresolved mixed/modal
command can remain at the player's head while the world reader progresses.
A slot still cannot be reused until both readers release it. The dispatcher
must apply its owned effects before acknowledging, preserve field cutoffs,
and invalidate all outstanding private records on lifecycle rebase. Acknowledging
a matching record is not proof that no producer fault arrived immediately
after the final fault check; scheduler/recovery checks still apply. Conversely,
a fault before acknowledgement does not undo effects already applied by the
dispatcher: its recovery accounting must distinguish those from unapplied
commands rather than blindly replaying the retained head.

The original command queue suite still passes 30,511 calls. The new
`test_command_ack_c.py` passes 69,498 calls across independently delayed
readers, repeated peeks, sequence/cursor wrap, field cutoffs, overflow,
pause/rebase and a retained mixed command. Modified sequence/key/reserved
bytes and stale acknowledgements reject without advancing a cursor.
`test_command_flags_c.py` adds 2,816 checks of result NZVC and register
preservation; wrapper restores use MOVEM to preserve result flags.
All 457 native input-adapter checks also pass after rebuilding the diagnostic
slave. Evidence: `tmp/dev/tmp/c/command-tests.json`,
`command-ack-tests.json`, `command-flags-tests.json` and `input-tests.json`.

`test_command_ack_preemption_c.py` interrupts acknowledgement at every
instruction boundary for both readers, including full-ring cases before and
after the other reader releases its slot. All 252 cases preserve the private
record and unread slots; reuse occurs only after both readers release them.
Eighteen interleavings acknowledge with a newly latched producer fault,
confirming the need for the recovery checks above. The harness saves/restores
the full CPU context, including deferred arithmetic flags. Evidence:
`tmp/dev/tmp/c/command-ack-preemption.json`.

The operations do not themselves classify commands or solve the mixed 03
collective reset. That ordered effect and modal exits must be resolved before
the corresponding command is acknowledged by the player dispatcher.

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
reverse their order. The isolated helpers below now preserve that ordering; installing them in
the dual-reader dispatcher remains an integration obligation. Engine/resource/UI callbacks are not covered
by the immediate-control fixture.

### Ordered command 03 effects

`timing-control-mode.i` separates the mixed command without replaying its
collective reset against later input. Native +05132 toggles engine bit 4;
if the old bit was set, +0513A clears collective. The indicator call at
+05144 uses D0=14 and D1.b=0/2 for the old-clear/old-set cases. Full-word
comparison is retained: 0803 is not command 0003.

`control_mode_init` takes a two-byte mode shadow a0 and player a1 and
copies the current bit as 0/1. Initialize only at a synchronized command
lifecycle epoch. `control_mode_command` takes those pointers and full command
d0.w: at the command's field it toggles the shadow, clearing player collective
only when the old shadow bit was set. It never changes the actual engine
byte. Return is 1 handled, 0 other command or -1 invalid shadow. The common
yaw tail remains a separate once-per-continuing-command action.

`control_mode_world` takes player a0, validated native indicator callback
a1 (+0AF36), and full command d0.w. At the world-command boundary it toggles
the actual bit and invokes the indicator with native arguments, preserving
all non-result registers. It deliberately omits the collective clear and
yaw tail already handled at field time. For example, starting with bit 4 set,
commands 03 then 51 leave collective at 1 even when the world reader consumes
03 afterward. Repeating the native whole decoder would incorrectly clear it.

`control_mode_check` compares shadow and actual bit only when both readers
have reached the same cutoff. Divergence/invalid shadow returns -1 without
repair. World changes to the engine byte, initialization, load/replay and
modal lifecycle must reconcile this state explicitly before later fields;
do not reinitialize the shadow from a world reader that is still behind.
An aligned opcode scan finds the direct bit-4 toggle at +05132 and a read at
+07ED8; this is not proof that whole-byte/lifecycle writes cannot change it.

`test_control_mode_c.py` compares 3,584 cases against the full native decoder
across all engine-flag bytes, seven collective values and commands 0003/0803.
Forty-eight ordered tapes combine mode toggles with collective, yaw, view and
modified commands in batches of 1/3/10/25. Player-owned state agrees after
each command, and the complete player plus indicator-call sequence agree
when the world reader catches up. Three invalid shadows and an intentional
actual-bit divergence reject/detect without silent repair. The native
indicator is stubbed while D0/D1.b and call order are checked; this is not
validation of its rendering internals. Evidence:
`tmp/dev/tmp/c/control-mode-tests.json` (22,030 helper calls).

These helpers resolve the isolated ordered reset. The queue dispatchers below,
indicator callback internals and boundary policies still need native installation
and live validation before C3 can be closed.

### Retained player command dispatcher

`timing-command-dispatch.i` classifies all 41 explicit full-word comparisons
in native +04ED4..+05334: 15 player controls, mixed 03, 13 world-primary words
and 12 lifecycle/display/navigation boundaries. Other words have no native
primary effect but still run the common yaw tail. The modified 0804/0805/0806
checks occur *after* that tail and remain world-primary actions. Boundary
words are 45, 0833, 0C, 40, 1C, 41, 37, 21, 22, 34, 42 and 46; they require
an explicit owner before either reader can continue past them.

`control_command_class` takes d0.w and returns 0 unknown, 1 player, 2 mixed
mode, 3 world, 4 boundary, preserving other registers. The source table is
checked against the native comparison operands, not inferred from key names.

`control_player_next` takes a 24-byte context in a0 and the field's recorded
command cutoff in d0. Initialize its queue/player/mode pointers at 0/4/8 and
zero the rest. It peeks at most one player command, records sequence/key at
12/16, then applies player or mixed-mode primary effects plus the shared yaw
tail. World-primary and unknown commands receive only that tail. It finally
acknowledges the player reader; the world reader is untouched. Return 1 means
applied and acknowledged, 0 none due, 2 retained boundary, or a negative
queue/state error. The boundary return performs no tail or primary effect
and leaves that command and all later commands retained.

`CP_COMMITTED` at 18 reports whether this call applied its field effects;
`CP_APPLIED` at 20 counts processed ordinary commands. Both are updated before
acknowledgement. A producer fault can therefore return an error with effects
already committed and the command still retained. Recovery must account for
that event rather than replay it. A subsequent faulted call applies nothing.
The scheduler/lifecycle owner must check upstream state and stop on boundaries.
This is a one-command primitive; field draining and native installation remain
caller responsibilities, not an unbounded loop inside the dispatcher.

`test_command_dispatch_c.py` verifies all 41 native compared words and 1,106
classification cases including modifier variants and unknowns. Sixteen queued
tapes across batching 1/3/10/25 and sequence wrap match native player/control
results as the independent world reader catches up. All 12 boundaries remain
at the head, all 13 world-primary words perform only the field yaw tail, and
invalid mode state preserves the command/player. The indicator callback is
stubbed; other world effects and modal execution are not exercised. Evidence:
`tmp/dev/tmp/c/command-dispatch-tests.json` (3,774 calls).

`test_command_dispatch_fault_c.py` injects a producer fault at acknowledgement
entry after a collective increment. The increment remains applied exactly once,
`CP_COMMITTED=1` and the lifetime count records it, but neither reader cursor
advances. A retry reports the queue fault without repeating the increment.
Evidence: `tmp/dev/tmp/c/command-dispatch-fault-tests.json`.

The world dispatcher below handles ordinary primary actions; boundary handlers
remain pending. World processing must not invoke the original common tail or repeat field
control primaries after this reader has already applied them.

### Native world command dispatcher

`timing-world-commands.i` copies native +04ED4..+05334 (1,122 bytes) and
replaces the first four bytes of the yaw tail at +052CC with a branch to
+052FA. Relative positions and native primary actions remain unchanged,
including reserve/damage checks and the modified 0804..0806 post-tail actions.
`world_commands_prepare` validates the entry, tail, post-tail comparison and
return before writing. Caller-provided version validation, non-overlapping
storage and an instruction-cache flush remain mandatory.

`world_command_step` takes player a0, prepared decoder a1, native indicator
a2 and full command d0.w. The classifier gates entry to the clone: only the
13 world-primary words enter it. Mode 03 uses the separate ordered helper;
field/unknown commands return 0 without effects, and boundaries return 2.
This guard is essential: native lifecycle exits pop an extra stack return
and cannot be invoked through this ordinary wrapper. Direct arbitrary-key
calls into the clone are not supported. Non-result registers are preserved.

`control_world_next` takes a 28-byte context a0 and deadline cutoff d0.
Initialize queue/player/decoder/indicator pointers at 0/4/8/12 and zero the
rest. It peeks, dispatches and acknowledges one world-reader command, never
advancing the player reader. Sequence/key are recorded at 16/20. Boundaries
remain retained without effects. `CW_COMMITTED` at 22 records completed
dispatch (including a no-op) before acknowledgement; `CW_APPLIED` at 24 counts
processed ordinary commands. Fault recovery must account for a completed
dispatch whose acknowledgement failed, just as for the player reader.

`test_world_commands_c.py` passes 2,240 native comparisons covering all 14
world/mixed primary words, damage combinations, empty/nonempty reserves and
resource stocks, and varied flags. Player/global results and callback order
match native primary effects while preserving the field-owned yaw and
collective values. Real resource decrement and derived weight code execute;
notification, indicator, weapon display and resource display callbacks are
stubbed. Eight boundary/no-op cases do not enter the decoder, and four
corrupted patch boundaries preserve destination storage. Evidence:
`tmp/dev/tmp/c/world-commands-tests.json`.

`test_dual_command_dispatch_c.py` connects both readers across 24 queued
tapes at batch sizes 1/3/10/25 and 32-bit sequence wrap. Mixed field controls,
engine toggles and weapon selections match native player state when the world
reader catches up; both readers retain all 12 boundary words. Callback stubs
remain as above. `test_world_command_fault_c.py` injects a producer fault after
an engine toggle but before acknowledgement: the changed engine state and
processed count survive, the world cursor remains retained, and a faulted retry
performs no duplicate toggle or callback. Evidence:
`tmp/dev/tmp/c/dual-command-dispatch-tests.json` (4,769 calls) and
`tmp/dev/tmp/c/world-command-fault-tests.json`.

Native callback internals, modal handlers, field/world loop routing and live
CPU validation remain pending; these queue readers are not installed yet.

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

## Fraction-aware approach response

`timing-response.i` implements the scalar approach terms used by vertical
rate (quarter), powered RPM (eighth), and forward speed (sixteenth).
It does not include speed's separate signed slew or the additive unpowered
RPM path. Angular response needs its own modular-error interpretation.

`response_step` takes a0 = signed long fractional state with denominator
32767, d0 = sign-extended native word error (target minus integer state),
d1 = response shift 2/3/4, and d2 = PAL 50 or NTSC 60. It returns an integer
increment in d0 and status 0/-1 in d1, preserving other registers. The
caller adds the increment using the native state's width. Invalid input
leaves the fraction untouched. Whole-tick fixture rate 3 requires zero
fraction and performs the original word-width rounding-bias addition and
arithmetic shift exactly, including overflow behaviour.

The flight-rate components now call `response_step_native`, which has the
same API but preserves the native zero-increment interval. After validating
the request, it computes the native word-width biased/shifted increment.
At field rates, if that increment is zero it returns zero and retains
the incoming fraction unchanged; otherwise it uses `response_step`.
Whole-tick mode is unchanged. The target may change each field, but has
no fractional component in this API.

Retaining the existing fraction is essential: forward response shares its
fraction with additive slew. Clearing it whenever the response stops
would erase most of a field's slew and could prevent acceleration.
The separate slew and coasting paths still run at their scaled rates.
This wrapper preserves native integer stopping states rather than
continuing an exponential approach inside them. The generic exponential
and fractional-target APIs remain available. Heading/track now use
`response_step_target_native`: the same native integer stopping rule,
with fractional-target feedback retained outside the zero-increment
interval. Neither the target fraction nor a shared additive fraction can
create an approach increment inside that interval. Complete coupled
acceptance bounds remain required.

The new wrapper passes 35,159 assembled calls covering the stopping
intervals and surrounding values with positive/negative fractions,
10,000 random word errors, whole-tick overflow boundaries and invalid
inputs. Fourteen PAL/NTSC trajectories settle at the same integer value
as native rounding after 30 seconds and remain unchanged for another
second. Evidence: `tmp/dev/tools/test_response_native_c.py`,
`tmp/dev/tmp/c/response-native-tests.json`. Generic exponential-response
accuracy results below continue to describe the ungated API.

The updated connected-motion suite retains all 4,096 native h=1 matches,
20,000 exact linear conversions, 6,000 field-model cases and 15 invalid
states. Another 880 consecutive PAL/NTSC forward-speed fields verify that
positive/negative additive slew remains exactly 3/rate per field while
the approach response is inside its stopping interval. Evidence:
`tmp/dev/tmp/c/kinematics-tests.json` (84,250 calls).

For field rate F and native shift k, the gain is
`alpha = 1 - (1 - 2^-k)^(3/F)`. Constants retain sixteen fractional bits
beyond the numerator for denominator 32767:
`G = round(alpha * 32767 * 65536)`. The 68000 uses split unsigned-word
products with explicit sign handling, avoiding floating point or 64-bit
instructions. The six constants are checked against 60-digit Decimal
evaluation in the test harness.

Let `P(x) = trunc(x * G / 65536)`. For integer error e and signed fraction
f, the update forms `T = P(e) + f - trunc(P(f)/32767)`, returns
`q = trunc(T/32767)` and retains `T - q*32767`. Thus the target error includes
the old fraction; it is not recomputed solely from the visible integer
state. Product truncation is below one fraction unit, not a whole native
state unit. Each response quantity needs independent fractional storage
and explicit lifecycle/impulse/saturation handling.

`response_step_target` additionally accepts a target main fraction in d3,
with the same denominator and bounds as the current fraction. Its numerator
adds `trunc(P(target_fraction)/32767)` to T. Thus a track response can
follow the newly integrated heading's fraction rather than only its byte.
The ordinary `response_step` passes a zero target fraction. Whole-tick
fixture mode requires both fractions to be zero. Smaller rate-conversion
residues stay retained by the caller and are each below 1/32767 native unit.

This is a scalar response component, not the complete field motion step.
The caller still must apply native derived targets, update order, wrapping,
slew, clamps and world effects. The complete player h=1/held-input gate
cannot be inferred from this arithmetic check.

`tmp/dev/tools/test_response_c.py` passes 246,315 calls, including 196,608
comparisons with returning copies of original native instructions: every
signed-word error for quarter/sixteenth rounding, and every byte target/old
RPM pair for the powered eighth response. Twenty thousand random field
cases match an independent integer model, including signed fractions.
Invalid parameters preserve state and non-result registers are checked.
For each rate/shift pair, nine constant targets spanning small values and
near signed-word limits are followed for ten seconds. The largest observed
difference from the ideal exponential trajectory, including retained
fractions, is below 0.0021 native units. This is a measured bound for those
scalar fixtures, not all changing targets or coupled flight dynamics.
Evidence: `tmp/dev/tmp/c/response-tests.json`.

## Stage-connected flight rates

`timing-flight-rates.i` owns a 24-byte caller-supplied state. Byte offsets
in this table are hexadecimal:

| Offset | Contents | Unit / reset obligation |
|---|---|---|
| 00 / word | Field rate 50/60, or whole-tick fixture 3 | Initialized with the player epoch |
| 02 / word | Reserved, initialized to zero | Initialization |
| 04 / long | Vertical response fraction | Denominator 32767; clear on vertical-rate reset |
| 08 / long | Forward response fraction | Denominator 32767; clear on speed reset |
| 0C / long | Forward slew conversion remainder | Denominator rate; clear with forward fraction |
| 10 / long | RPM response fraction | Denominator 32767; reset with initialized RPM |
| 14 / long | RPM additive conversion remainder | Denominator rate; reset with RPM fraction |

For quantities with both fractions, the full retained amount is
`main/32767 + conversion/(rate*32767)`. `fraction_add_rate` in
`timing-fraction.i` adds an exact 3/rate linear increment into this shared
representation. It divides in native units before converting the residue,
keeping every 68000 division quotient in range. This avoids maintaining
independent whole-unit debts for response and slew. The response feedback
sees the main fraction; the extra conversion remainder is below 1/32767
native unit and remains retained for subsequent additive updates.

`flight_rates_init` validates the rate and clears all fractions.
The component entry points take state in a0 and a private player record
in a1, return d0=0/-1, and preserve other registers:

* `flight_vertical_step` takes native stage-1 terms in a2. It replaces the
  whole vertical-rate result using the captured target and old rate,
  **before** the height stage reads the new rate.
* `flight_forward_step` takes stage-3 corrected error and slew in a2.
  It **replaces stage 4**, applying the sixteenth response and then the
  exact-time signed slew. Stage 5 reads the resulting speed from the record.
* `flight_rpm_step` runs after native stage 6 has built its RPM target,
  with d0 holding the RPM byte saved **before** that stage. Powered RPM
  uses the eighth response. Coasting recomputes the native unclamped
  additive change from collective, coarse speed and ground state, scales
  that change, then clamps to 0..156. It clears outward fractional debt at
  saturation while preserving inward debt.

Every component validates the entire fraction state before writes.
Whole-tick fixture mode requires zero fractions. World ground resets must
clear the vertical and both forward fractions alongside the native bytes;
initialization/rebase must reset the full state consistently. Powered/coasting
transitions share the RPM fraction rather than silently discarding it.
These obligations are not yet connected to the native lifecycle.

`tmp/dev/tools/test_flight_rates_c.py` passes 71,078 calls. Interposing these
components into all seven native motion stages at h=1 produces complete
player records identical to the whole deterministic preview in 4,096
airborne/low-altitude cases. Twenty thousand signed linear-conversion
cases preserve exact rational totals, and 6,000 randomized PAL/NTSC
component cases match independent full-fraction models. Fifteen malformed
state cases, including signed-long extremes, fail without writes.
Evidence: `tmp/dev/tmp/c/flight-rates-tests.json`.

Angles and displacement use the separate components below. The rate
functions alone must not be installed as a complete player step. World
effects, full coupled-flight acceptance and CUSTOM1-gated native installation
are still pending.

## Coupled heading and track angles

`timing-heading.i` owns 20 bytes: rate/reserved words, then heading main
fraction, heading conversion remainder, track main fraction and track
conversion remainder. Their units match the flight-rate shared fractions.
`heading_init` initializes rate 50/60 or whole-tick fixture 3 and clears
all fractions. `heading_step` takes state in a0, private player in a1,
heading/track bytes saved **before native stage 0** in d0/d1, and a supplied
world heading impulse (-2..2) in d2. It replaces stage 0's angle results
after native power calculation. It returns d0=0/-1, preserves other
registers, and validates state/inputs before writes.

The yaw branch retains native byte doubling of the yaw control, scales
that additive rate, then derives track from heading and the roll-sign
offset. Track inherits heading's fractions because this is a derived
angle, not a separate damped response. In the bank branch, the native
arithmetic-shifted roll supplies an additive rate to both angles. Heading
uses the sixteenth response toward track; track then uses the quarter
response toward the **newly updated** heading, including its main fraction.
The yaw control is cleared on the bank path as in native code.

Both bank responses preserve their native zero-increment intervals.
This matters even with a moving fractional target: the previous ungated
response accumulated a small positive heading correction on top of the
bank's additive rate. In a held roll-16 turn, native heading advances
four angle units per world tick. The old field path gained an extra
2.231 PAL / 1.859 NTSC angle units over a minute. Keeping native stopping
intervals prevents that fractional approach term from changing the turn
rate while preserving the per-field additive bank motion. Evidence for
the pre-correction eight one-minute tapes is retained in
`tmp/dev/tmp/c/horizontal-before-angle-stops.json`.

After applying the stopping rule to both angular responses, all four
one-minute roll-16 bank tapes (configuration 0/2, PAL/NTSC) match native
heading at every whole-second sample, including retained fractions.
Track differs by at most three angle units. Native track sees an entire
new heading increment before its response; the finer sequential steps
produce a different relative phase without changing the additive turn
rate. The maximum sampled horizontal separation across the eight
forward/bank tapes is 38.331 map units. This is measured scope, not a
general maneuver or collision acceptance bound.

In the four straight-line tapes, the position offset is constant over the
last ten seconds: -18.98/-19.30 map units in configuration 0 and
-16.38/-16.20 in configuration 2 (PAL/NTSC). Thus those differences settle
after acceleration rather than representing an ongoing speed error.
Evidence: `tmp/dev/tools/measure_horizontal_motion_c.py`,
`tmp/dev/tmp/c/horizontal-motion-measurement.json`.

The revised angle component retains 102,400 native h=1 comparisons,
12,000 independent field-model cases, all five supplied heading impulses
and four invalid-state checks. The complete coordinator also retains
4,096 whole-motion matches, 2,640 composed field steps and nine rollback
cases. Evidence: `heading-tests.json` and `kinematics-step-tests.json`
in `tmp/dev/tmp/c/`. Input reversals, other bank angles, nonzero initial
speed/track mismatch, world effects and collision consequences remain
part of the broader C4e/C5 gate.

Native rounding biases wrap in byte width before the heading/track shifts.
For the sixteenth response, the effective error is
`sign_extend_byte(raw_difference + 8) - 8`; the quarter response uses +2/-2.
Passing these word errors to the response core preserves the native h=1
result even at the biased wrap thresholds. A generic shortest-angle
subtraction would not reproduce those cases.

The supplied damage-heading impulse is applied at full magnitude **after**
the track update, matching native order. This helper does not draw RNG
values or decide damage eligibility. Grounded state freezes angles and
fractions and rejects a nonzero supplied impulse. Bank/yaw transitions
preserve heading state and explicitly derive/reset track fractions on the
yaw path. Mission initialization/rebase must initialize these fractions
consistently with the native pose; the native lifecycle is not yet hooked.

`tmp/dev/tools/test_heading_c.py` passes 102,400 h=1 comparisons against
the original power/heading code, including every heading/track byte pair,
yaw branches, roll signs, ground cases and all five captured native random
impulses. Complete player records match and helper calls leave RNG unchanged.
Twelve thousand PAL/NTSC cases with nonzero fractions match an independent
coupled-angle model; four malformed state cases fail without writes.
The existing response and flight-rate regression suites also pass.
Evidence: `tmp/dev/tmp/c/heading-tests.json`.

The combined `test_flight_heading_c.py` fixture interposes heading/track and
vertical/forward/RPM components into the same native stage sequence.
All 4,096 whole-tick candidate records still match the complete deterministic
preview. Its retained linear-conversion and flight-rate checks also pass
(79,270 calls total). This verifies their ordering together; displacement
is still native whole-tick code in this fixture, and world effects remain
excluded. Evidence: `tmp/dev/tmp/c/flight-heading-tests.json`.

## Height, horizontal displacement and wind

`timing-movement.i` owns 20 bytes: rate word, pending-contact word,
height/x/y signed long fractions (each denominator rate), previous-height
airborne word, and a reserved word. `movement_init` accepts 50/60 or h=1
fixture 3 and clears the state. Component functions take state in a0 and
a private player record in a1, return d0=0/-1 and preserve other registers.
They validate all fractions and bookkeeping flags before writes.

`movement_height` **replaces native stage 2**. It retains the original
byte-width addition of vertical rate and `(tick & 1) + 1`, arithmetic
shift by two, word-width height addition and signed zero floor. The
resulting native-quantized height rate is scaled by 3/rate with a retained
fraction. Outward debt is cleared at the floor. The private record must
contain the logical tick parity for the interval being consumed; choosing
that epoch in the native scheduler remains a hand-off obligation.
This helper does not advance the world clock.

After the zero floor, height is normalized to its integer floor plus a
nonnegative fraction below one. If the retained fraction is negative, the
helper subtracts one from the integer height and adds one denominator to
the fraction. The represented altitude is unchanged. For example,
`1024 - 3/60` becomes `1023 + 57/60`. Native lift calculations then see
the crossed high-byte boundary immediately, rather than continuing to use
the old height until another whole unit of descent accumulates.
Input validation still accepts a signed height fraction; every successful
height step produces the normalized representation. Whole-tick fixture
mode has zero fractions and is unaffected.

`test_height_normalization_c.py` checks 18,432 combinations of PAL/NTSC,
all vertical-rate bytes, both tick parities, signed input fractions and
heights around zero, integer and high-byte boundaries. The expected
integer/fraction pair comes from Euclidean division of the exact rational
height after the ground floor. Register/stack and contact flags are also
checked. Evidence: `tmp/dev/tmp/c/height-normalization-tests.json`.
The existing 4,608 native height comparisons, 65,536 native horizontal
comparisons, 8,000 field models and 4,096 combined native h=1 cases still
pass after normalization.

This also makes the integer ground predicate see height zero for a
positive physical altitude below one native unit. The world adapter must
use the documented integer representation consistently; C5 collision
acceptance remains required rather than treating this normalization as
proof of collision equivalence.

The height step records whether its input height was nonzero and latches
a nonzero-to-zero crossing. `movement_ack_contact` clears only the pending
crossing after world evaluation. It does not decide landing severity,
crashes, flight end or notifications, and a crossing flag is not a substitute
for the C5 committed-state/contact comparison. A later rise does not silently
erase an unconsumed crossing.

`movement_horizontal` **replaces native stage 5** and takes the validated
native sine helper (+07A44) in a2. It derives coarse speed with the native
word shift and signed-byte narrowing, then obtains exact native sine/cosine
increments from the immutable helper/table. Each axis scales movement,
adds it with native word wrapping, and applies the unsigned 1800..D800 hex
bounds. Outward fractions are discarded at a bound, preserving inward
fractions. Airborne wind is then scaled and added **after** both coordinate
clamps, without a second clamp, matching native order.

Movement and wind share each axis's fraction, so neither contribution
loses a sub-unit increment or acquires a separate whole-unit debt. Heights,
coarse speed and trigonometric rates retain native quantization; this does
not invent extra velocity precision in the native table inputs.
The selected integration order uses each field's newly updated rates.
It therefore follows finer semi-implicit integration, rather than forcing
old whole-tick endpoint displacement. That trajectory difference must be
measured separately from rounding in the full held-input gate.

`tmp/dev/tools/test_movement_c.py` passes 4,608 original height comparisons,
including byte parity/wrapping and signed-word floor boundaries, and
65,536 original horizontal comparisons covering every coarse-speed/angle
pair, map edges and signed wind. Eight thousand PAL/NTSC full-fraction
models verify update order, clamps, contact latching and acknowledgement.
Six corrupt-state cases reject before writes. Evidence:
`tmp/dev/tmp/c/movement-tests.json` (164,297 calls).

The `test_kinematics_c.py` fixture now connects heading/track, vertical
response, height, forward response, horizontal motion/wind and RPM in native
order. All 4,096 h=1 complete player records match the full deterministic
motion preview; its fraction/model regressions also pass (83,366 calls).
Evidence: `tmp/dev/tmp/c/kinematics-tests.json`. This is the continuous
candidate gate, with world RNG/contact effects excluded. It is not proof
of a complete native tick, field-rate handling bounds, collision equivalence,
live input latency, CPU cost or production installation.

## Continuous motion coordinator

`timing-kinematics.i` connects the motion components in a single
`kinematics_step` call. Its 64-byte state concatenates flight-rate,
heading and movement shadows. `kinematics_init` accepts 50/60, or 3 for
the whole-tick fixture. The step takes state/player in a0/a1, prepared
native stages in a2, the validated native sine helper in a3, and a supplied
world heading impulse in d0. It returns d0=0/-1 and preserves other registers.

The order is native stage 0 then scaled heading/track; stage 1 then scaled
vertical response; scaled height; stage 3 then scaled forward response;
scaled horizontal motion/wind; stage 6 then scaled RPM. It saves the old
heading, track and RPM before their native stages overwrite them. All
components must have the same rate. The caller supplies the interval's
logical tick parity and validated, cache-flushed native code.

The routine computes on stack copies of the player record and shadows.
Only a successful complete step copies both back; an invalid late component
cannot leave earlier motion partially applied. This is foreground error
rollback, not an interrupt-atomic publication protocol. Scratch is 174 bytes,
plus the saved registers and nested callees' stack use; C4f must price the
copies and nested calls as well as the arithmetic.

The coordinator also exposes `kinematics_prepare` and
`kinematics_complete`, with the same a0..a3 pointers and a separate
174-byte candidate in a4. Prepare advances through height without changing
the original player/shadow. The candidate holds its 64-byte shadow at +0,
player at `KN_PLAYER=64`, intermediate terms and a phase word at
`KN_PHASE=172`. Successful preparation sets phase 1. Completion requires
phase 1 and consumes it before running forward/displacement/RPM; it publishes
only after those stages succeed. Repeated completion is rejected. A failed
prepare leaves phase 0; a late completion failure cannot publish or be
retried. Callers must keep the original state stable while a candidate is
outstanding and serialize its use. `kinematics_step` wraps these same two
operations with a private stack candidate.

This exposes the exact ground boundary to the world adapter. A test places
12 bytes of attitude state immediately before the candidate so
`player_ground_step` can apply its combined reset to the candidate shadow
and candidate player. In 4,096 h=1 comparisons, including 2,480 ground
resets and 241 notifications, completing that candidate matches native
motion. Repeated completion and invalid preparation/late fractional-state
failure leave authoritative state unchanged. Evidence:
`tmp/dev/tmp/c/split-ground-motion-tests.json`.

The split does not make external side effects transactional. Native ground
notifications and timers must be deferred until completion succeeds in the
production adapter; the fixture compares successful paths with notification
UI stubbed. Choosing contact eligibility, integrating attitude at this split,
and routing the actual world deadline remain pending.

The assembled coordinator passes 4,096 complete-record comparisons with
the native deterministic whole-tick preview. Twenty-four two-second
PAL/NTSC sequences (2,640 fields total) match the separately invoked
component chain in every player byte and all shadow state, including
supplied heading impulses. Nine invalid-rate, fraction, bookkeeping or
impulse cases leave the original state/player unchanged; invalid
initialization also leaves state unchanged. Register and stack contracts
are checked. Evidence: `tmp/dev/tools/test_kinematics_step_c.py`,
`tmp/dev/tmp/c/kinematics-step-tests.json` (41,445 calls).
The field sequences verify composition, not the C4e native-versus-finer
trajectory bound, which remains pending.

This routine covers continuous flight arithmetic only. Input decoding,
control commands, stick attitude and its world impulses precede it.
Pitch-clamp placement, world RNG eligibility/contact consequences,
fraction resets on lifecycle transitions and the native scheduler adapter
remain integration obligations. It is not included in the slave yet;
installation must use the CUSTOM1 Enhanced framerate gate.

## Fractional camera angles

`timing-camera.i` adds `player_camera_angles`, a read-only presentation
adapter. It takes the player in a0, combined player-step state in a1
and a 12-byte camera vector in a2. It replaces only the heading, pitch
and roll words at offsets 6/8/10 after `presentation_build`; positions
and instruments remain that builder's responsibility. It returns
d0=0/-1 and preserves other registers. Invalid rates or angle fractions
leave all output untouched.

In PAL/NTSC mode, heading includes both its main and conversion fractions.
The camera contribution is the exact integer quotient
`trunc((main*rate + conversion)*256 / (32767*rate))`, using two bounded
68000 signed divisions. Roll includes `trunc(roll_fraction*256/rate)`.
The adapter uses the committed player state and retained integration
fractions; it does not predict future player input or motion.

Field-mode pitch uses a linear half-angle after native byte negation,
plus `-trunc(pitch_fraction*128/rate)`. This deliberately removes the
native integer half-pitch staircase: otherwise, for example, pitch 0
and -1 both produce camera angle 0, hiding small initial pitch inputs.
At odd integer pitch, the enhanced angle can differ from the native
camera by 128 angle-word units (half an angular unit); it does not change
the authoritative pitch or flight equations. Native byte-negation wrap
is retained. Whole-tick fixture rate 3 requires zero fractions and uses
the exact original byte-negation/arithmetic-shift camera operation.
This distinction is explicit: zero fractional state at field rate does
not imply native camera equality for odd pitch.

Repeated presentation neither consumes controls nor changes player,
fractional or RNG state. This adapter still needs CUSTOM1-gated native
installation and live input-to-screen validation; changing camera words
in a CPU fixture alone does not prove display latency.

`tmp/dev/tools/test_camera_c.py` passes 65,536 native angle comparisons
(all pitch/heading byte combinations with varied roll/view), 12,000
independent PAL/NTSC fraction models, and eight invalid-state cases.
Eight first-field stick cases cover both signs of x/y at both rates:
pitch and roll camera words already change after one player step.
One hundred repeated camera builds per case preserve the exact angles,
player/shadow state and gameplay RNG seed. Output guards verify that only
the three angle words change. Evidence:
`tmp/dev/tmp/c/camera-tests.json` (221,450 calls).

## Combined continuous player step

The standalone `timing-player-step.i` now provides a common continuous
player entry point above attitude and kinematics. Its 76-byte state
concatenates the 12-byte attitude state and 64-byte kinematics state.
`player_step_init(a0, d0=rate, d1=previous_y)` initializes both components
or rejects invalid input without writes. `player_step` takes state,
player, prepared native stages, sine helper and an immutable 10-byte
input packet in a0..a4. The packet contains signed words for x/y direction
and supplied roll/pitch/heading impulses. Both entry points return d0=0/-1
and preserve other registers.

The step applies the authoritative pitch clamp, then attitude, then flight
arithmetic, which reads the newly
updated integer attitude. Retained attitude fractions are not substituted
into native table inputs. It checks matching rates, operates on
stack copies and publishes the player and both shadow states only after
success. A late flight/heading rejection therefore cannot consume the
previous-y input or partially apply an attitude change. This outer
transaction adds 162 scratch bytes and saved registers on top of the
nested kinematics transaction; stack high-water and CPU cost still need
the C4f check.

This entry point does not decode the native history records or keyboard
commands, decide world-impulse eligibility, or perform world
contact/weapon effects. The caller must
schedule those operations and supply the logical tick parity. The
native adapter and CUSTOM1-gated installation remain pending.

`player_step_interval` accepts the same pointers plus d0 = the logical
interval tick (0..65535). It substitutes that value only in a private
86-byte player copy so native vertical rounding sees the upcoming
interval's parity. On success it restores the original tick word before
publishing the result. Thus field-rate motion cannot advance the displayed
world clock; the native world owner still increments that counter once
per deadline. Invalid interval values and rejected player steps leave the
record and shadow state unchanged. This entry adds another player-record
copy to the C4f stack/cost accounting.

`attitude_pitch_clamp` applies native +05756..+05776 byte/BMI semantics
before each consumed field's controls, not on repeated renders. It clears
the pitch fraction when the integer is clamped or when a fraction points
outward at exactly -12/+20, and preserves inward fractions. It validates
rate and pitch fraction before writes; previous-y and roll state remain
unchanged. The combined transaction rolls back this clamp too if a later
input or motion check rejects the field. Native whole-tick ordering is
clamp, controls, motion; world recoil still belongs after motion and is
seen by the next consumed field's clamp.

The clamp passes 3,840 native-byte/fraction combinations, repeated
idempotence checks, and five invalid-state cases. Evidence:
`tmp/dev/tools/test_pitch_clamp_c.py`,
`tmp/dev/tmp/c/pitch-clamp-tests.json` (11,527 calls).

The assembled step passes 4,096 complete player-record comparisons
against the original clamp, deterministic attitude and native motion
preview at h=1, now covering every initial pitch byte. The fixture
suppresses random attitude eligibility with
airborne/no-damage input; motion-preview world omissions still apply.
Another 1,320 fields exercise holds, reversals, neutral controls and
supplied impulses at PAL/NTSC, comparing every player and shadow byte
with the separate components. Ten early/late failures leave state and
player unchanged, three invalid initializations preserve state, and
register/stack/input-packet checks pass. Evidence:
`tmp/dev/tools/test_player_step_c.py`,
`tmp/dev/tmp/c/player-step-tests.json` (17,605 calls).
This proves composition; the fractional camera adapter is tested
separately above, while measured input-to-screen latency remains open.

## Composed field-path verification

The composed field-path fixture now runs actual history publication,
scheduler delivery, control decoding, `player_step_interval`,
acknowledgement and fractional camera code together. For each of PAL and
NTSC it consumes the same 240-field changing-control/button tape in
batches of 1, 3, 10 and 25. Every per-field player/shadow state, every
world-boundary observation and the final camera angles are identical
across batch sizes. The scheduler refuses another delivery while either
player or world completion is pending. Button edges accumulate only until
their corresponding world observation.

The native counter begins at 65532: all PAL runs finish at 10 after
14 world observations; all NTSC runs finish at 8 after 12. Every player
step is checked to leave the authoritative tick unchanged. The world
test callback increments it explicitly. This callback is an observer,
**not native AI/weapon/contact execution**; keyboard commands and live
interrupt interleavings are also outside this fixture. Native installation
and those ownership boundaries remain open.

Direct comparisons of `player_step_interval` with `player_step` on an
explicitly substituted private tick cover both parity values, 65535,
three original counters and rates 3/50/60. Evidence:
`tmp/dev/tools/test_field_pipeline_c.py`,
`tmp/dev/tmp/c/field-pipeline-tests.json`.

## Coupled held-control measurement: C4e not accepted

`tmp/dev/tools/measure_held_motion_c.py` runs 32 ten-second comparisons:
eight scenarios, configuration byte 10 equal to 0/2, and PAL/NTSC.
Scenarios hold collective and initial attitude with no new stick input:
level attitude, climb/descent settings, forward pitch, bank, yaw, wind and
engine coasting. Initial coordinates are 7000/8000 hex, altitude 1024,
RPM 128 and speed/vertical rate zero. Powered cases set engine flags to
1C hex (both engine-enable bits and powered response); coast sets zero.
The bank case uses pitch 8 and roll 16, within native control limits.

The reference runs native deterministic motion at three ticks per second;
the candidate runs `kinematics_step` every field. Each field uses its
logical interval's tick parity. Samples at exact whole seconds compare
integer native state against candidate integer-plus-fraction state.
All cases remain airborne and away from map limits; world effects, new
stick input, collisions and presentation are outside this measurement.
Pre-correction evidence:
`tmp/dev/tmp/c/held-motion-before-native-stops.json` (18,594 calls).

Maximum absolute differences across the sampled ten seconds:

| Quantity (native units) | Field path versus native | PAL versus NTSC field paths |
|---|---:|---:|
| x coordinate | 14.44 | 0.37 |
| y coordinate | 30.75 | 0.61 |
| Height | 12.30 | 0.22 |
| Forward speed | 2.174 | 0.100 |
| Vertical rate | 2.052 | 0.097 |
| RPM | 2.492 | 0.040 |
| Heading (256 units/turn) | 0.342 | 0.057 |
| Track (256 units/turn) | 2.882 | 0.090 |

The largest sampled horizontal distance difference is 30.840 map units.
These are observations, **not accepted rounding bounds**. In particular,
the configuration-2 level-attitude case exposes a persistent equilibrium
change: native vertical rate settles at -2, whereas fractional exponential
response approaches -4. After ten NTSC seconds, native altitude is 1009
and candidate altitude including fraction is 996.75. Native powered RPM
stops at 153 while the candidate continues toward its target of 156.

The native response's rounding creates a zero-increment interval. For
quarter response, error -2 gives `(-2 + 2) >> 2 = 0`; for eighth response,
error +3 gives `(3 + 4) >> 3 = 0`. Applying a pure exponential below a
whole tick removes these native stopping ranges. This is a handling
change that can accumulate displacement indefinitely; it must not be
described as a small residual rounding error. The revised integer-target
response now preserves the native zero-increment interval as described
above. The original measurements are retained in
`held-motion-before-native-stops.json`; they describe the pre-correction
implementation. The coupled gate still needs moving targets and
fractional heading/track acceptance coverage.

Repeating all 32 runs after the stopping-range correction preserves the
native integer RPM equilibrium: the configuration-2 NTSC level-attitude
case ends at 153 plus 0.009980 fraction, versus native 153. Its vertical
rate now stops at -3 plus -0.008149 fraction instead of approaching -4.
However, native rate is -2 and the altitude difference remains 12.25
units after ten seconds. Maximum sampled height difference remains
12.30, while the maximum single-axis coordinate difference is 32.55.
The correction therefore fixes the isolated response equilibrium rule,
but **does not pass the coupled handling gate**.

The field trace isolates a delayed integer-height boundary. In NTSC field
36 the represented altitude is 1023.95 but the record still contains 1024.
Lift consequently keeps vertical target -5 until field 76, rather than
switching to -4 when the boundary is crossed. Vertical rate reaches -3
in field 64 and stays there. The native second tick has already lowered
its record to 1023 and settles at rate -2. Evidence:
`tmp/dev/tmp/c/height-feedback-before-normalize.json`.

Normalizing height to floor-plus-positive-fraction addresses this
representation error without changing the integrated physical altitude.
A valid native stopping interval can contain several integer rates;
preserving that interval alone did not guarantee that the coupled field
trajectory entered it at the same integer as the native tick. The
post-stopping-range, pre-normalization measurements above are retained in
`tmp/dev/tmp/c/held-motion-before-height-normalize.json`.

After normalization, NTSC field 36 publishes integer height 1023 plus
57/60. Field 37 therefore switches the target to -4, and integer vertical
rate remains -2, matching the native equilibrium. In the 32 repeated
ten-second tapes, the previously divergent level/yaw/wind configuration-2
cases stay within 0.72 PAL / 0.75 NTSC height units of native state and
within 0.021 vertical-rate units including fractions. Across all tapes,
the maximum sampled height difference falls from 12.30 to 6.76 units.
Horizontal differences remain up to 32.55 on one axis, so this fixes the
identified feedback bug without closing the full C4e gate. Current
evidence: `height-feedback-trace.json` and
`held-motion-measurement.json` in `tmp/dev/tmp/c/`.

The affected level-attitude case also passes a full-minute PAL/NTSC
regression with the same maxima, 0.72/0.75 height units and less than
0.022 vertical-rate units. The discrepancy does not grow over this
window. `tmp/dev/tools/test_height_feedback_c.py` asserts the bounds;
evidence is `tmp/dev/tmp/c/height-feedback-regression.json`.

Separately, finer integration has an intentional displacement difference
even without rounding: N equal semi-implicit steps under constant
per-tick acceleration A travel `v0 + A*(N+1)/(2*N)`, versus the native
single-step `v0 + A`. Four steps give the playbook's `v0 + 5*A/8`;
20 NTSC steps give `v0 + 21*A/40`. The design retains finer integration,
but that does not justify changing a settled native velocity. The full
C4e gate remains unpassed until these two effects are separated and the
remaining trajectory differences have an explicit acceptance bound.

## Native world ground boundary

`timing-ground.i` extracts the unchanged +095A0..+09636 block into a
152-byte returning code buffer. `ground_prepare` takes the validated
0658 code hunk, destination and hunk 6 in a0/a1/a2. It checks the entry,
notification call target, timer destination and reset stores before copying;
the caller must flush instruction caches before execution.

`ground_step` takes the authoritative player in a0, prepared code in a1
and an explicit pre-height airborne flag (0/1) in d0. It returns 0 without
effects when current altitude is nonzero, 1 after ground processing, or -1
for an invalid flag. Other registers are preserved. The native block keeps
its landing/crash arithmetic, notification call with argument 7, flight-end
write and timer write. It clears speed, pitch, roll and vertical rate even
when the supplied flag says the player was already grounded.

This is an authoritative world operation, not a speculative preview.
It belongs after height and before forward-speed response, coordinates
and RPM. Invoking it after the complete continuous coordinator would move
the resets past their native consumers and fail h=1 ordering. The world
adapter must therefore expose that intermediate boundary, clear the
corresponding speed/vertical/attitude fractions on a reset, and finish the
remaining continuous stages afterward. It must validate the candidate
before invoking externally visible notification effects.

The native pre-height flag and the field path's pending crossing flag
serve different purposes. The adapter still needs a tested policy for a
crossing followed by a rise before the next world deadline; this helper
does not choose one or consume the pending flag. Once-only scheduling,
collision equivalence and the native notification routine's complete
effects remain open. The helper is not installed in gameplay and its
eventual installation must use the CUSTOM1 gate.

The extracted block matches the original in 10,000 grounded/airborne
cases, including 1,947 notification calls. The fixture compares the whole
player record, notification count/argument and timer, and verifies register
and stack preservation. Three invalid flags and 36 corrupted signature
bytes reject without destination/player writes. The notification routine
itself is replaced by a recording stub; its UI effects are outside this
test. Evidence: `tmp/dev/tools/test_ground_c.py`,
`tmp/dev/tmp/c/ground-tests.json`.

The combined h=1 motion fixture inserts this block immediately after
scaled height, then executes scaled forward response, displacement and
RPM. All 4,096 complete player records, notification counts and timer
values match a whole native-motion reference with only heading RNG
excluded. The cases include 2,480 ground resets and 241 notifications;
signed-height overflow cases exercise the latter. Evidence:
`tmp/dev/tools/test_ground_motion_c.py`,
`tmp/dev/tmp/c/ground-motion-tests.json` (61,443 calls).
This confirms the intermediate ordering at h=1; field-rate contact
history, fractional resets and actual notification UI remain outside it.

## Combined player ground hand-off

`timing-player-ground.i` connects native `ground_step` to the combined
`PS_SIZE` fractional state. `player_ground_step` takes shadow a0, player a1,
prepared native ground block a2 and the world-selected pre-height airborne
flag in d0. It returns the native wrapper's 1/0/-1 status and preserves
other registers. Native notification and timer writes remain real.

On a ground reset it clears roll/pitch remainders, vertical response,
both forward-speed fractions and fractional height, then acknowledges the
pending height-crossing latch. The zero-height contact snaps sub-unit
altitude to ground. It preserves previous stick input, heading/track,
RPM, horizontal coordinate fractions and the last height-step airborne
flag. Native ground code does not reset those quantities. An airborne
result or invalid flag leaves all fractional state untouched.

`test_player_ground_c.py` compares 10,000 native ground decisions with
varied valid PAL/NTSC/h=1 shadow states: 6,666 resets and 1,903 notification
cases agree with the native block. All bytes outside the reset ownership
set remain unchanged, including airborne/invalid cases. Notification UI
is stubbed while its argument/count and real timer write are compared.
Evidence: `tmp/dev/tmp/c/player-ground-tests.json`.

`test_player_ground_motion_c.py` places the hand-off at that boundary in
4,096 complete h=1 staged motion comparisons, including 2,480 resets and
241 notifications. Player results, notification count and timer match the
whole native motion reference. Heading RNG is excluded in both paths and
notification UI is stubbed. Evidence:
`tmp/dev/tmp/c/player-ground-motion-tests.json`.

The helper must run after height and before forward-speed/displacement/RPM,
not after a complete `player_step`. The split kinematics boundary now exists; the production coordinator still
needs to route it through the combined player path, with once-only world scheduling and a policy for a height
crossing followed by departure before the next world deadline. This helper
does not establish swept collision equivalence or C5b acceptance. It is
not called by ordinary fields or installed into the game yet.

## Deferred ground side effects

`timing-ground-deferred.i` makes the native ground boundary usable on a
private motion candidate. `ground_deferred_prepare` first uses the existing
validated ground extraction, then replaces the six-byte notification call
with a six-byte write of native D0.w to a private event record. It redirects
the timer store to that record's byte +2. The native MOVEQ supplies message
7; notification +0A150 preserves registers, and the following native
instruction replaces the condition codes. All ground classification and
candidate-player writes remain native.

The event is four bytes: notification word, timer byte, ready byte. Prepare
takes the original a0/a1/a2 code/destination/hunk6 arguments plus its stable
event address in a3. Flush caches after preparing the clone. The event must
be separate from all code/player/shadow storage.

`ground_deferred_step` takes candidate PS shadow a0, candidate player a1,
deferred clone a2, the bound event a3 and airborne flag d0. It rejects a
nonempty event, then evaluates through `player_ground_step`, including
fraction resets. Success records either `00000001` (no external effects) or
`0007B401` (message 7, timer 180). No live timer or notification is touched.
Invalid flags do not alter the candidate/event. Candidate failure requires
an explicit event discard; do not commit merely because evaluation succeeded.

After motion completion and publication, `ground_deferred_commit` takes
event a0, native notification entry a1 and live timer address a2. It validates
the complete event, clears it before calling out, then performs notification
followed by the timer write in native order. Return values are 1 for applied
effects, 0 for a valid decision with no effects, and -1 for invalid/not ready.
Repeated commit is rejected. All three helpers preserve non-result registers.
The foreground caller still owns serialization and once-per-deadline scheduling.

`test_ground_deferred_c.py` passes 10,000 native comparisons, including
6,666 player resets and 1,965 notifications. Evaluation preserves the live
notification counter and timer; commit matches native results, and pending
re-evaluation/double commit cannot duplicate effects. Three invalid airborne
flags and 36 corrupted extraction signatures reject. Notification UI remains
stubbed while its arguments/count are checked. Evidence:
`tmp/dev/tmp/c/ground-deferred-tests.json`.

`test_deferred_ground_motion_c.py` evaluates the deferred boundary, completes
the split motion and only then commits effects. All 4,096 h=1 native-motion
comparisons pass (2,480 resets, 241 notifications). A candidate with a pending
notification and deliberately invalid late speed fraction fails without
publishing motion or applying the notification/timer. Explicit discard and
five malformed commit records are checked. Evidence:
`tmp/dev/tmp/c/deferred-ground-motion-tests.json`.

This supplies deferred effects for the split coordinator, but does not yet
install that coordinator, decide swept contact eligibility or integrate the
full world tick. Original ground notification UI and live VBL interleavings
still need the production validation gate.

## Combined player boundary candidate

`timing-player-boundary.i` exposes the height boundary without bypassing
controls or private interval parity. `player_boundary_prepare` takes the
normal player-step pointers (a0 shadow, a1 player, a2 stages, a3 sine,
a4 packet), separate candidate storage in a5 and the logical interval tick
in d0. It copies the input state, applies the authoritative pitch clamp and
stick/impulse attitude, then prepares kinematics through height. Original
player/shadow remain unchanged, including the authoritative tick.

The 350-byte candidate starts with contiguous PS shadow/player at offsets
0/76, so `ground_deferred_step` accepts those pointers directly. Its
kinematics phase is at 184. A separate temporary PS/player workspace at
186 avoids aliasing the kinematics inputs/outputs; saved authoritative tick
is at 348. Persistent candidate storage and nested call cost still require
C4f measurement on the 68000.

`player_boundary_complete` uses the same pointers and candidate (packet/d0
input ignored). It finishes kinematics into private workspace, restores the
saved authoritative tick there, includes the boundary's attitude-fraction
resets, and publishes the complete player/shadow only on success. Failed
or repeated completion changes neither original. Commit the separate ground
event only after this returns success; discard it if completion fails.
The caller must keep originals stable while the candidate is outstanding
and serialize all evaluation/completion/publication. Publication is not
interrupt-atomic, matching the existing foreground player-step contract.

`test_player_boundary_c.py` passes 1,356 steps across rates 3/50/60,
changing controls and supplied impulses, matching `player_step_interval`
in every player/shadow byte while leaving the authoritative clock at 65535.
Another 4,096 comparisons run native pitch clamp, native stick attitude and
whole native motion with ground restored: 2,527 resets and 241 notifications
match the combined candidate plus deferred commit. Native disturbance RNG
is disabled in those reference cases and notification UI is stubbed.
Repeated completion and invalid interval/control/late fraction cases reject
without publishing. Evidence: `tmp/dev/tmp/c/player-boundary-tests.json`.

This entry is available for the world-deadline path but not installed.
It does not generate impulses, consume commands, increment the world clock,
select contact eligibility, or route the scheduler. Ordinary field stepping
still uses the existing entry until the world adapter is assembled and
validated. Full C4e/C5 collision and cross-CPU acceptance remain pending.

## World-owned motion impulse generation

`timing-world-impulses.i` now supplies the native random-motion
eligibility and generation boundary. `world_motion_impulses` takes the
authoritative player, 10-byte player-step packet and validated native RNG
entry in a0/a1/a2. It replaces only the three impulse words, preserves
control directions and all other registers except result d0=0, and never
applies the impulses to the player.

It calls the original RNG in roll/pitch/heading order. Roll requires
damage bit 0 in byte 0F and produces -4/0/+4. Pitch requires a zero high
height byte, unsigned speed word at least 8, and low height byte below
the low speed byte, producing -1/0/+1. Heading requires nonzero height
and either damage bit 0/1, producing -2..+2. These eligibility fields
are unchanged by intervening native attitude and stage-0 arithmetic,
so generation can precede applying the supplied impulses. Other native
RNG users must still retain their original relative order.

The helper is authoritative, not a preview: its native RNG calls change
the real seed. The world adapter must call it once per world deadline
after the correct native clock/input setup, and ordinary fields must
receive zero impulses. The helper does not itself enforce scheduling or
select replay behavior. Its eventual native installation is CUSTOM1-gated.

Native RNG mode 0 reads input-event timestamp longs at hunk 2 +0014/+0018;
mode 1 reads the authoritative player tick. Native +0E8A/+0E92 copy the
InputEvent seconds/microseconds into those locations; these are not VBL
counters. Each field record now retains both raw longs at offsets 32/36.
Deferred consumption must use the deadline record's values rather than
those of a later input event. The world adapter must still bind these
recorded values without overwriting producer-owned live input state.
Matching RNG under frozen inputs is not proof of render-independent live RNG.

The expanded records pass 457 native-adapter cases and 132 instruction-boundary
history interruptions. The composed field pipeline checks the timestamp bytes
on every delivery and includes them in every world-deadline observation:
240 fields at each of 50/60 Hz produce identical observations for batches of
1, 3, 10 and 25. This validates transport, not native RNG binding or live
interrupt timing. Existing live captures used the older diagnostic layout;
the updated capture reader expects `GSIH0002` and the full 5,140-byte history.

`test_world_impulses_c.py` passes 3,840 native comparisons over both RNG
modes, damage combinations, ground/low/high altitude, signed speed
boundary values and varied seeds/ticks. Captured impulse triples,
draw counts (0..3) and final seeds agree with native attitude followed
by native heading. Memory-write checks permit only impulse words, RNG
seed and stack; player/control bytes remain unchanged. Evidence:
`tmp/dev/tmp/c/world-impulses-tests.json`. Live deadline sampling and
once-only scheduling remain integration gates.

## World RNG bound to a deadline

`timing-world-rng.i` prepares a 108-byte copy of native 0658
+07A5C..+07AC6. It redirects only the two input timestamp operands to
`TR_RNG_MICROS`/`TR_RNG_SECONDS` in a stable private field record. The
native seed, replay-mode flag, authoritative tick, branches and arithmetic
remain unchanged. Its entry at +0 supplies bound 256; +10 retains the
native stack-bound entry; +14 accepts the bound in D1.w. No temporary writes to live input memory are
needed, so a new input event cannot be lost through save/restore.

`world_rng_prepare` takes the validated native RNG address in a0, separate
even code storage in a1, the private record address in a2 and the native
input hunk in a3. It checks both input operands and entry/return boundaries
before writing anything, returns 0/-1 and preserves other registers.
The caller must validate the game version, provide non-overlapping storage
and flush instruction caches after preparation. The record address stays
fixed; its contents change only between world updates. Calls retain the
native RNG ABI and still mutate the authoritative seed.

`test_world_rng_c.py` passes 2,880 comparisons across all three native entries,
zero/nonzero replay-mode values, varied seeds/ticks/timestamps and bounds
1, 3, 256, 32767 and 65535. The reference uses the deadline timestamp in
live input; the clone uses the same timestamp privately while live input
contains unrelated bytes. Result registers and seed agree, and write
tracing permits only the seed and stack. Nine corrupted patch-boundary
cases reject without touching destination storage. Evidence is
`tmp/dev/tmp/c/world-rng-tests.json`.

The composed `GS_TEST_DEADLINE_RNG=1 test_world_impulses_c.py` fixture
also passes all 3,840 native impulse comparisons with unrelated live input.
Roll/pitch/heading impulses, draw counts and final seeds match; the private
record and live input remain unchanged. Evidence is
`tmp/dev/tmp/c/world-impulses-deadline-tests.json`.

This is not installed gameplay: all native world RNG callers still need
routing through the prepared entry in their original order, with the
scheduler's private deadline record held stable. Renderer effects must
be separated before redirecting shared native RNG entry points. Replay
setup, lifecycle, cache handling and CUSTOM1-gated installation remain
integration obligations.

## Native RNG caller inventory (0658)

`audit_rng_callers_c.py` scans the exact relocated original hunk extents for
absolute JSR/JMP and relative BSR/BRA targets at all three RNG entries.
The following twelve external direct calls occur in hunk 0; the additional
+07A62 branch is internal to the RNG. No direct caller of the stack-bound
+07A66 entry was found. This opcode scan is not a proof about indirect
calls or reachability; the sites below were also inspected at their native
instruction boundaries. Evidence: `tmp/dev/tmp/c/rng-callers.json`.

| Call offset | Entry | Observed operation / timing owner |
| --- | --- | --- |
| +05380 | +07A5C | Roll disturbance; world impulse |
| +053DC | +07A5C | Low-altitude pitch disturbance; world impulse |
| +0598E | +07A6A, D1=128 | Periodic main-loop housekeeping after reserve consumption; world |
| +07D98 | +07A5C | Damage eligibility draw before native tick/level checks; world |
| +07DC6 | +07A5C | Select damage bit to set in player +0E; world |
| +09480 | +07A5C | Heading disturbance; world impulse |
| +099FA | +07A5C | Weapon/launch eligibility arithmetic before slot allocation; world |
| +09C04 | +07A6A, D1=256 | Effect X displacement; world-owned spawn |
| +09C1A | +07A6A, D1=256 | Effect Y displacement; world-owned spawn |
| +09C2A | +07A6A, D1=16 | Effect height displacement; world-owned spawn |
| +09E30 | +07A5C | Damage/event threshold after effect spawn; world |
| +0A0EA | +07A5C | Scripted-event threshold before coordinate setup; world |

Effect constructor +09B9A has three direct call sites: +05C92 in the render
path, and +09E2A/+09E56 in the world damage/event path. The constructor
allocates first and returns without RNG if no slot is available; otherwise
it consumes three draws in X/Y/height order. In particular, +09E2A can
consume three draws *before* the +09E30 threshold draw, and +09E56 can
consume another three afterward. Those world-side calls must retain their
native order and allocation outcome. Moving or suppressing the whole
constructor would silently change gameplay RNG. C7a must instead move the
render-path invocation, including its eligibility and pose inputs, to a
world boundary. +05C8A tests hunk 6 +42F7 before that invocation.

The +07A6A register-bound entry is used by actual gameplay and rendering;
redirecting only +07A5C/+07A66 would miss four external calls. The prepared
clone exposes `WR_REGISTER_ENTRY=$0E`; its tests now cover arbitrary upper
D1 bits while preserving the native low-word bound. Shared native entry
redirection remains pending until render-side spawning is removed and all
world calls have the correct deadline record available.

## Effect constructor with private world inputs

`timing-world-effects.i` copies native +09B9A..+09C3C into a 164-byte
constructor. It redirects the three RNG calls to the deadline RNG's
D1-bound entry and the heading read to a private word. The native allocator,
sine helper, effect tables, arithmetic, a5 pose ABI and register clobbers
remain unchanged. This makes the inputs explicit without temporarily
replacing renderer or interrupt-owned storage.

`world_effect_prepare` takes validated code hunk a0, code storage a1,
prepared deadline RNG a2 and private heading address a3. It validates the
allocator call, failure branch, heading-load opcode, return and three RNG
call targets before writing the destination. The caller owns storage,
version validation and instruction-cache flushing. The constructor retains
the native zero-draw allocation-failure path and X/Y/height draw order.

`test_world_effects_c.py` compares 1,024 executions across both RNG modes,
all 64 pool-occupancy masks, varied poses, headings and seeds. The reference
uses native input/heading storage; the clone uses private deadline inputs
while live input and render heading contain unrelated values. Output
registers, pool masks, effect tables and seed match. Draw counts are zero
for a full pool and three otherwise. Write tracing permits only seed,
allocation masks, effect tables and stack; player and private/live inputs
remain unchanged. Eleven malformed preparation cases preserve destination
storage. Evidence: `tmp/dev/tmp/c/world-effects-tests.json`.

The render-side eligibility byte hunk 6 +42F7 is decremented at +04C32
inside the +04B48 VBL callback. It already measures fields, not rendered
frames: do not move that countdown to 3 Hz. Its world-side setters write
64 or 128 fields at +09E22/+09E48. The +05C92 render invocation tests it
at +05C8A. Its deadline value still needs history or an explicit lifecycle
policy so catch-up does not consult a later field's countdown.

The native heading source hunk 6 +390A lies in the renderer's camera vector
(start +3904). +04390 writes intermediate vectors and +0440A writes the
completed vector; extra rendering can therefore change the constructor's
heading input. The world adapter must supply the appropriate committed
heading explicitly. The extracted constructor alone does not establish
the render caller's a5 pose, choose that heading, move the invocation, or
change VBL effect animation. Those remain C7 integration work; this helper
is not installed into gameplay.

## Field-rate deterministic attitude

`timing-attitude.i` implements the continuous portion of native
+05376..+053C4. `attitude_init` initializes a 12-byte caller-owned state:
rate word, previous-y word, signed long roll remainder and signed long pitch
remainder. It accepts PAL 50 or NTSC 60; rate 3 is exclusively the h=1
fixture mode. The caller supplies the prior normalized y direction at
initialization/rebase. `attitude_step` takes state in a0, player record in
a1, and normalized x/y directions (-1/0/+1) in d0/d1. It returns d0=0
or -1 for invalid input/state, preserving other registers. Invalid calls
do not partially change player bytes or fractions.

Each field scales roll's `4*x` and pitch's `-(current_y+previous_y)`
(only when current y is nonzero) by exactly 3/rate. Pitch retains byte
wrapping. Roll retains native byte wrapping before its -20..20 clamp.
At roll saturation only outward fractional debt is discarded, so it
cannot accumulate against the stop and delay a later reversal.
Ordinary release retains sub-unit motion rather than silently dropping it.
Previous y advances once per consumed field.

The previous-input window is intentionally one field in the responsive
path. Keeping it at one world tick would preserve a 333 ms control-history
window. This has a quantified effect distinct from numerical rounding:
for a held new vertical direction, initialized with any prior direction,
one second of field steps differs from three native steps by at most
47/25 (PAL) or 19/10 (NTSC) native pitch units including retained fractions.
The worst case is reversal. This is a component-level bound for that
specified input history, not a bound on arbitrary manoeuvres or a claim
that the full flight-equivalence gate has passed.

The world still owns generation/eligibility of the damage-roll and
low-altitude pitch perturbations. `attitude_step_impulses` has the same
interface plus d2 = roll impulse (-4/0/+4) and d3 = pitch impulse (-1/0/+1).
It applies these at full magnitude, without timestep scaling. Roll combines
with stick input **before** the roll clamp; appending it after an
already-clamped field step would not preserve h=1 at the limits. Pitch is
added after continuous pitch control, as in the native routine.
`attitude_step` is the zero-impulse entry point for ordinary fields.
Both preserve non-result registers and reject invalid impulses before writes.

The native world adapter still has to generate eligible impulses once in
the correct RNG order and deliver them to the appropriate field step.
An impulse record must not be replayed on subsequent fields or lost during
catch-up/rebase. The authoritative HUD pitch clamp is a separate ordered
helper called by the combined player entry point before the attitude
step. The low-level `attitude_step` entries still do not clamp pitch or
generate RNG.

`tmp/dev/tools/test_attitude_c.py` compares 55,296 h=1 cases directly with
the original deterministic attitude routine: all direction triples, all
256 roll bytes, and eight pitch values including wrapping boundaries.
Complete player records match with damage disabled and altitude high
enough to exclude the random pitch branch. Another 3,960 field steps
compare against an independent rational model across PAL/NTSC, saturation,
release, reversal, random inputs and render batches of 1/3/10/25. Six
invalid input/state cases preserve both record and state. Held-input
tests also verify the stated history-window difference using the assembled
field step and its native-equivalent h=1 mode.
Evidence: `tmp/dev/tmp/c/attitude-tests.json`.

`tmp/dev/tools/test_attitude_impulses_c.py` captures the actual native
random outcomes and supplies them to the h=1 impulse entry point.
Across 68,040 cases spanning both native RNG modes, damage, height/speed
eligibility, all direction triples, roll-limit crossings and pitch wrapping,
complete player records match the original routine. All nine roll/pitch
impulse pairs occur. Fifty-four PAL/NTSC cases verify full impulse magnitude
at field rates; six invalid impulse cases leave state unchanged.
Memory-write hooks observe only player/state/stack writes, and the gameplay
RNG seed remains unchanged during helper calls. The deterministic suite
also passes after this change. These checks prove impulse application;
production RNG scheduling and consumption are still pending.
Evidence: `tmp/dev/tmp/c/attitude-impulse-tests.json`.

This state must join the production lifecycle manifest and reset alongside
the input history and player pose. It is not wired into gameplay yet.
Sub-unit attitude in the camera, the rest of the motion integrator and
native input/world ownership are still pending; these tests do not prove
next-render input latency in the running game. Installation must share
the CUSTOM1 Enhanced framerate gate.

## Scheduler/player boundary bridge

`timing-field-player.i` binds a delivered scheduler field to the combined
player candidate. Its 40-byte context contains six caller-initialized
pointers (shadow, player, stages, sine, packet, candidate), followed by the
bound scheduler pointer, field stamp, command cutoff and two status words.
Initialize the latter sixteen bytes to zero. `FP_BOUND` is at 36 and
`FP_COMMITTED` at 38. Original state and context remain foreground-owned.

`field_player_prepare` takes context a0, scheduler a1, private history record
a2 and interval tick d0. It requires player-pending scheduler phase, matching
field/cutoff, matching player/display rates and unfaulted upstream state.
The caller must already have decoded input and applied the correct commands
and impulse policy. Success prepares the candidate and binds its identity;
it neither publishes player motion nor acknowledges the scheduler.

After any private world-boundary evaluation, `field_player_complete` takes
the context in a0. It rechecks scheduler identity and upstream faults,
finishes/publishes the combined player candidate, then calls
`scheduler_player_done`. Success returns 0 for another field or 1 for a due
world update. No world acknowledgement is performed: the native world owner
must still complete that update before delivery can continue.

Failures before publication consume the binding and invalidate the candidate
phase without acknowledging the field. `FP_COMMITTED` stays zero, so any
candidate ground event must be discarded. A producer can fault after
publication but before/during acknowledgement; in that case the existing
scheduler counts the applied step, returns a fault, and `FP_COMMITTED=1`
records that motion really committed. The recovery owner must account for
that applied work and any corresponding deferred event. Repeated completion
is rejected; inspect the return status and commitment flag together. No
claim of interrupt-atomic multiword publication is made.

`test_field_player_c.py` consumes 240 fields at each of 50/60 Hz in batches
of 1/3/10/25 (1,920 fields total). Player/shadow, camera output, timestamp
transport and world-deadline observations agree across batches. Delivery
remains blocked during a pending player candidate and during each due world
update. Eight wrong identity/rate/control/interval/upstream/late-state cases
reject without publication or acknowledgement. A fresh emulator instance
injects a producer fault at acknowledgement entry: the bridge reports the
fault with `FP_COMMITTED=1`, and the scheduler counts exactly one applied
step. The test uses a world observer, not native AI/weapons/contact execution.
Evidence: `tmp/dev/tmp/c/field-player-tests.json` (17,829 calls).

This bridge is standalone. Native accepted-command dispatch, impulse timing,
world contact selection, world execution and CUSTOM1-gated installation are
still pending. It supplies the scheduler connection without inventing those
policies or acknowledging an unexecuted world tick.

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
`tmp/dev/tools/test_timing_cores.py` exercised 112,847 calls: PAL/NTSC
deadlines over two minutes, field and cursor wrap, invalid configuration,
gaps, pause/rebase accounting, full-ring preservation and random FIFO
traffic. Composition tests consuming 600 fields in render batches of
1, 3, 10 and 25 produced identical field order and world deadlines.
Non-result registers and stack/return behaviour were checked.

`tmp/dev/tools/test_history_preemption.py` additionally interrupts the real
consumer at every instruction boundary, runs the producer, restores the
interrupted CPU state (including deferred arithmetic flags via full emulator
context save/restore) and resumes the consumer. All 132 cases pass at
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

### Bounded command drains at scheduler phases

`timing-command-phase.i` connects the retained command readers to the
scheduler's delivered cutoff. `command_phase_player` requires player phase 1;
`command_phase_world` requires world phase 2. Both take the scheduler in a0,
the matching CP/CW reader context in a1 and a command budget of 1..128 in d0.
They validate that the reader uses the scheduler's command queue, check all
upstream owners before and after each dispatch, and preserve non-result
registers. They never acknowledge player motion or world execution.

Return 0 proves the reader has drained the delivered cutoff; 2 leaves a
lifecycle command retained for its owner. Return -2 means the command budget
was exhausted: resume the same phase, including when the last command happened
to empty the queue. Negative queue/upstream errors require explicit recovery;
reader COMMITTED/APPLIED accounting still distinguishes effects that preceded
an acknowledgement failure. A successful command drain is a prerequisite for
motion/world work, not evidence that those steps have completed.

`tmp/dev/tools/test_command_phase_c.py` passes 20 assembled integration
scenarios (417 calls): both readers with budgets 1/3/10/128, ordinary and mixed
mode commands, sequence wrap, future commands beyond the cutoff, actual
scheduler player/world acknowledgements, wrong phase/queue/budget rejection,
upstream fault rejection and retained lifecycle boundaries. It checks register
preservation, reader cursors and completed-step counters. UI callbacks are
stubbed. This adapter remains standalone; native main-loop installation,
lifecycle handling and full command/player/world composition remain pending.

### Enforce command completion before preparing field motion

`field_player_prepare` now peeks the player reader at the delivered cutoff
before constructing a motion candidate. An unread ordinary command or lifecycle
boundary returns -3 without advancing the queue, changing the player/shadow or
binding a candidate. Commands beyond that cutoff do not block this field.
The caller uses `command_phase_player` to drain ordinary commands first;
retained lifecycle boundaries still need their explicit owner. Packet decoding
and once-per-world impulse selection remain caller responsibilities.

`tmp/dev/tools/test_field_command_player_c.py` exercises this composition for
1,920 fields (240 fields at 50/60 Hz with batches 1/3/10/25; 26,199 assembled
calls). Every field publishes a command alongside changing sampled stick input.
The test first proves motion preparation rejects the unread command, drains the
player reader, prepares/completes motion, then drains the world reader at due
world boundaries. Player states, fractional state, camera output and world
observations match across batch sizes. The tape includes collective, yaw,
unknown commands and mixed mode-03 commands; mode shadows reconcile at world
cutoffs. Native UI callbacks are stubbed, and a world observer still replaces
full world execution. This proves composition/batch independence, not C4e
native trajectory acceptance or installed cross-CPU behavior.
The bridge regression also passes its eight existing invalid-state cases and
post-publication fault injection, plus retained ordinary/lifecycle commands
and a future-only command (130 calls). A future-only command is accepted;
the test's aggregate `rejected_cases` label includes that positive case.

### Native world-tick opening

`timing-world-start.i` extracts +05640..+056D8, ending before the HUD and
camera builders. It increments the 16-bit tick, decrements byte 4A if nonzero,
masks engine flags against damage, disables engines and clears their two
indicator bytes when both reserves are empty, initializes crash state 52 to 2
when appropriate, and decrements countermeasure lifetimes 44/45. Expiry calls
the native +07EEE inventory/indicator routine in original order. All these
writes belong to one world tick, never a render or speculative player step.

`world_start_prepare` takes hunk 0, an even clone buffer, hunk 6 and the bound
player in a0/a1/a2/a3. It validates the entry, relocated lamp stores, callback
calls and player reloads before copying 152 bytes plus RTS. Only the two player
reload operands are redirected; native indicator state and callbacks remain
real. The caller must flush caches. `world_start_step` takes that player/clone
in a0/a1, rejects mismatched binding, preserves non-result registers and returns
0 on completion. Execution is authoritative and cannot be rolled back.

`tmp/dev/tools/test_world_start_c.py` passes 560 native comparisons covering
tick values 0/15/16/65535, cooldown values 0/1/2/36/255, seven engine flag
patterns and four reserve values. Complete player bytes, indicator stores and
ordered indicator IDs/values match. The native +07EEE dispatcher runs; only
its final +0AF36 UI operation is stubbed. Thirteen signature corruptions reject
without destination writes; mismatched runtime player binding also rejects
without world writes (575 assembled calls total).

This is not the full world tick. Placement relative to commands and field
motion remains an integration gate: native opening precedes controls/motion,
while field motion spans a world interval. Reserve depletion is a distinct
post-motion operation every sixteenth tick (+0590C..+0598A), not part of this
opening. The periodic +07F80 flight-end check can set player 18 before reserve
depletion; its scratch-word inputs follow the masked tick test. Preserve that
ordering when extracting the remaining housekeeping. No native installer calls
this helper yet; eventual installation must use CUSTOM1 Enhanced framerate.

### Periodic flight-end check and reserve depletion

`timing-world-reserves.i` preserves the native every-sixteenth-tick branch
at +058AC. On due ticks it runs the unchanged +07F80 flight-end predicate;
if player 18 is nonzero it reports the cleanup boundary without consuming
reserves. Otherwise it executes +0590C..+0598A, retaining both reserves'
sequential dependency, engine-count scaling, damage additions, byte wrapping
and signed-word saturation. In particular the second reserve's depletion
observes the first reserve after its update. This is discrete world work,
not a per-field rate approximation.

`world_reserves_prepare` takes hunk 0 and an even clone buffer in a0/a1.
Both blocks are relocation-free; every source word is compared with the
0658 instruction image before any destination write. The output is 164 bytes
including the original guard RTS and an appended reserve RTS. Cache flushing
and nonoverlapping buffers remain caller responsibilities.
`world_reserves_step` takes authoritative player/clone in a0/a1 and preserves
non-result registers. Return 0 means no periodic work, 1 means reserves were
updated, and 2 requests flight-end cleanup. It neither advances the tick nor
performs cleanup or the following periodic RNG/housekeeping. The caller must
invoke it once after world motion/weapons/damage/script work, never per render.

`tmp/dev/tools/test_world_reserves_c.py` passes 4,096 comparisons with the
native control-flow entry +058AC, stopping at +058C6 (cleanup), +0598A (after
reserves) or +05A0C (no periodic work). Complete player bytes and branch outcomes
match: 1,536 nonperiodic, 1,658 reserve updates and 902 cleanup boundaries.
Inputs cover tick wrap boundaries, engine flags, collective extremes, damage,
empty/large reserves, RPM/height and crash/end states. All 81 source-word
corruptions reject before destination writes (4,178 assembled calls). This
helper remains standalone; full housekeeping, scheduler composition and
CUSTOM1-gated installation are still pending.

### Remaining periodic housekeeping with deadline RNG

`timing-world-periodic.i` extracts +0598A..+05A0C, replacing the loop-back
branch with RTS and redirecting its one bound-128 RNG call to the private
deadline RNG's register-bound entry. Call it once only when
`world_reserves_step` returns 1. Native object-table loads/stores, mission-table
swap and notification/map callbacks retain their order. A rejected random
threshold still consumes exactly one draw; no extra draws are introduced.

`world_periodic_prepare` takes hunk 0, an even destination, the deadline RNG
base and hunk 6 in a0/a1/a2/a3. It validates the entry, early-out branch, eight
relocated calls and two relocated global reads before writing. `WP_SIZE` is
136 bytes: 130 native bytes, RTS and the bound native player pointer.
`world_periodic_step` takes native player/clone in a0/a1 and returns 0/-1 with
non-result registers preserved. It rejects a different player address before
execution: +046DE can branch into +0475A, which reads the absolute native
player coordinates. The complete player and trailing object tables must be
present; an isolated 86-byte player copy is insufficient. Cache flushing,
once-only scheduling and deadline-record lifetime remain caller obligations.

The callback audit identified world-triggered presentation writes: +0475A
updates coordinate words in hunk 1 +0180..+0194, while +046DE can set the
+0192 word to 256. These writes are retained here and must be distinguished
from arbitrary render-frequency updates during the remaining map/timer audit.
The callback also changes hunk 4 notification bytes and hunk 0 +0A99E state.

`tmp/dev/tools/test_world_periodic_c.py` passes 512 native comparisons in both
RNG modes across 11 callback paths. The reference uses native timestamp memory;
the clone uses the same recorded timestamp while live memory deliberately
differs. Player/table bytes, seed, mission tables, notification/map state and
ordered callback arguments match. Write tracing permits only inventoried
state and stack; each execution draws once. Native +07B7E/+07BD0, +08036,
+07FBE and +046DE/+0475A run; audio endpoints +0B4E4/+0B57C are stubbed.
Twenty-two patch-boundary corruptions reject without destination writes, and
a mismatched player binding rejects without state writes (537 calls total).
This remains standalone. Full world sequencing, lifecycle/audio behavior,
map timer policy and CUSTOM1-gated installation are not yet validated.

### Complete periodic tail, including flight-end cleanup

`timing-world-tail.i` joins the reserve and periodic helpers and extracts native
cleanup +058C6..+0590C. Cleanup loads object slot 5 into player scratch, clears
its first coordinate word and stores it back, visits object entries 121 down
through 6, calls +0B726 for entries whose flag byte has bits 3/4 set, clears
hunk 0 +0BA08 and sets hunk 4 +01C6. The unchanged native removal call searches
its ten-byte list at hunk 0 +0B92D; its argument is the masked flag byte, not
the saved loop index. Preserve that native behavior.

`world_cleanup_prepare` takes hunk 0, an even 70-byte clone and hunk 4 in
a0/a1/a2. It validates loop boundaries, three relocated calls, two global
stores and RTS before copying. `world_tail_step` takes native player,
reserves clone, periodic clone and cleanup clone in a0/a1/a2/a3. It first
checks the periodic clone's player binding before any mutation, then selects
the native path. Returns are 0 (nonperiodic), 1 (periodic complete), 2 (flight
ended) or -1 (bad binding). Non-result registers are preserved. No tick is
advanced; the caller must already have completed opening, player motion,
weapons, damage and scripts. On return 2 the lifecycle owner must stop active
sampling and rebase before accepting another field. The adapter does not
perform that transition or acknowledge the scheduler itself.

`tmp/dev/tools/test_world_tail_c.py` passes 512 comparisons from native
+058AC through its actual return or loop-back boundary: 256 nonperiodic,
128 normal periodic and 128 cleanup outcomes. The comparison covers complete
player/object tables, reserves, mission/map/notification state, removal list,
flight-end flag, RNG seed and ordered callback arguments across 31 paths.
Native object helpers, list removal and map-coordinate work run; only the two
audio endpoints remain stubbed. Deadline timestamps match the reference while
live timestamps differ, with exactly one RNG draw for normal periodic work
and zero for the other outcomes. Write tracing reports no uninventoried
writes. Fourteen cleanup signature corruptions and a wrong player binding
reject without writes (531 assembled calls). Full world-loop integration and
CUSTOM1-gated gameplay installation remain pending.

### World fire flags and weapon-input audit

Native +04DC6 detects rising edges against the previous sampled buttons;
+04DE0/+04DEC increment two counters at hunk 0 +04E26/+04E28. The foreground
block +04E4C..+04E88 clears the two consumer flags at hunk 6 +04292/+04293,
sets each byte to 1 if its counter is nonzero, then clears that counter.
The flags are edge requests, not held-button levels. Preserve held state in
history/scheduler for its own consumers, but do not OR it into these flags:
that would introduce a repeated launch request on every tick while held.

`timing-world-fire.i` builds these two bytes in a private output buffer from
the scheduler's accumulated low two edge bits. `world_fire_prepare` takes
scheduler/output in a0/a1 and returns 0, -1 upstream failure or -3 wrong phase.
It requires world phase 2 and checks upstream health before and after packet
construction. It preserves non-result registers and does not acknowledge the
world, clear edges or touch native input latches. Discard the private packet
on failure; execute weapon work once before `scheduler_world_done` clears the
interval. Repeated preparation is not permission to repeat weapon execution.

`tmp/dev/tools/test_world_fire_c.py` passes 144 comparisons with the native
counter-collapse block (six values for each counter, four held masks),
including signed/high counter values and unrelated edge bits. Eight scheduled
runs cover 960 fields at 50/60 Hz, batches 1/25, a released brief press and a
long-held press. Each produces one request at the first deadline and none at
later deadlines, with identical results across batching. Three phase/fault
rejections leave the private output untouched (4,179 assembled calls).

The weapon block +0979C..+09B9A has a single direct RNG call at +099FA, to
native default-bound +07A5C. Its consumer-flag operands are +097B2, +097FA,
+09832, +0995A, +09A92 and +09B7A for the first byte (some operations are words),
and +0983C/+09854 for the second. The eventual extraction must redirect both
reads and clears to the same private two-byte packet and redirect the RNG
call, retaining native allocation, recoil and launch-pose arithmetic. Native
actor work at +0BED4 runs before launch selection; it still needs full routing
and state validation. No weapon clone or launch integration is installed yet.

Outside that block, scripted +0817A..+08198 waits for live button release and
a field-counter change, then clears the first edge counter and both consumer
flags at +0819E. This is a lifecycle boundary requiring sampling/rebase policy,
not ordinary deadline input. Replay also writes through the input block at
+05420..+05428. Those paths must be resolved before redirecting native weapon
latches in gameplay. All eventual installation remains gated by CUSTOM1.

### Native weapon block with private world inputs

`timing-world-weapons.i` extracts +0979C..+09B9A. It redirects all eight
consumer-flag operands inventoried above to one private two-byte packet,
including word reads/clears, and redirects +099FA to the deadline RNG's
default-bound entry. Native launch selection, ammunition checks, allocation,
pose arithmetic and recoil stay unchanged. The native +0BED4 actor call and
all other callbacks are retained; this extraction does not certify their
complete call trees for private RNG/state ownership.

`world_weapons_prepare` takes hunk 0, an even clone, deadline RNG base, private
fire packet and hunk 6 in a0/a1/a2/a3/a4. It validates entry/actor/RNG/return
boundaries and the opcode/address of each fire access before writing.
`WW_SIZE` is 1,026 bytes: 1,022 bytes of code including RTS, followed by the
native player binding. The caller owns stable nonoverlapping buffers and
flushes instruction caches. `world_weapons_step` takes native player/clone in
a0/a1, rejects another player pointer, preserves non-result registers and
returns 0/-1. Invoke once after committed motion and world command dispatch;
it applies real world effects and consumes only the private fire packet.
No scheduler acknowledgement, retry or rollback is performed here.

`tmp/dev/tools/test_world_weapons_c.py` passes 256 native comparisons with
four weapon selections, both RNG modes, all fire-bit combinations, varied
heading/pitch/altitude, empty ammunition, full allocation masks and an occupied
launch slot. Tests compare the full native memory interval 97EE00..99FFFF,
normalizing only timestamp and live-fire input storage, plus the remaining
fire packet and ordered callbacks. The clone leaves unrelated live fire bytes
77/88 untouched and uses the recorded timestamp despite different live input.
Eight callback paths include 24 default-bound RNG draws and 24 launch calls.
Native allocation, resources, launch arithmetic and recoil run. UI drawing
from ammunition exhaustion also runs: ordered blitter-register writes match,
but Unicorn does not validate rendered pixels. Write tracing permits native
memory, stack, the private fire packet and those blitter registers only.

The target lookup is a slot-5 fixture; notification/indicator/audio endpoints
+0A150/+0AF36/+0B4E4/+0B57C are stubbed. Actor update entry executes, but fixtures
have no active pre-existing projectiles in its update mask. Active-actor
motion/collision, nested RNG callers and actual target selection still need
separate validation. Twenty-three corrupted patch sites and a wrong player
binding reject without writes (282 assembled calls). This is not full C5/C9
acceptance, and no native main-loop installation has been added.

### Successive active-actor comparisons and VBL release ownership

`tmp/dev/tools/test_world_actor_sequence_c.py` extends the weapon comparison
to 64 consecutive ticks for four weapon selections in both RNG modes (512
matched ticks, 514 helper calls). It retains allocations between ticks and
initializes the actor-update eligibility word to native FFFF, rather than the
zero mask used to isolate launch tests. State, remaining fire requests,
ordered callbacks and hardware writes match at every tick while recorded and
live timestamps differ. Native target lookup remains a slot-5 fixture and
notification/UI/audio endpoints remain stubbed. There is no player integration,
world damage/script step or VBL effect-timer execution in this test.

Before guided release was exercised, types 1/3 correctly allocated but never
entered the active actor loop. Native constructor +0BBC8..+0BBD2 clears the
allocated slot's bit in hunk 0 +0BA0C for those types. The actor loop at +0BF22
intersects allocation word +0BA08 with that eligibility word; an allocated slot
is not automatically eligible for movement. Type 2 retains eligibility.

The expanded fixture executes the actual +0A22A..+0A248 release fragment at
tick 4 for types 1/3, with its control-state byte set to 5. This is an explicit
fixture transition, not validation of the complete native control-state
machine. For each RNG mode, type 1 then records 60 active-slot visits, 10 ticks
with coordinate changes and one +0C3E0 impact; type 3 records 60 visits,
13 moving ticks and one impact. Type 2 records 45 visits/moving ticks and one
+0C45E expiry. Type 0 records 258 visits to its stationary effect slots. No
+0C444 terrain-impact path was exercised. Full impact-to-world-damage handling,
terrain collision and effect lifetime validation remain pending.

Crucially, +0A1C8 is called from VBL callback +04C12, guarded by hunk 4 +01C6
being zero and hunk 0 +0A44E being nonzero. Its state-5 branch +0A234..+0A242
sets the eligibility bit using guided-slot word +0BA0E. Therefore native VBL
work can change whether a projectile advances at a world tick. Leaving that
write live while replaying older field history would allow a later field's
release to affect an earlier deadline. The eventual integration must preserve
this transition's field order and slot identity, alongside constructors and
world updates; copying a later eligibility mask over world state is not a
validated solution. This is an outstanding C3/C4h/C7 ownership obligation,
not covered by the standalone weapon clone or its private fire flags.

### Field-owned guidance progression and render-independent handshake

The release audit found a second dependency: +0A1C8's pending-display byte
(hunk 0 +0C757) is cleared by the screen-swap routine at +044CA. It waits on
this flag both when starting the guidance sequence and when completing state
30/31. Merely replaying the VBL routine while retaining that live flag would
still make projectile release/completion depend on render frequency.

`timing-field-guidance.i` extracts +0A1C8..+0A2F0 and removes its four display
calls (one +0A35A reset and three +0A2F0 sprite updates). Native phase,
activation, hidden-view, guided-slot and eligibility writes remain intact.
All four reads/writes of the pending-display byte are redirected to a private
byte; real screen swaps cannot acknowledge this private state. The caller must
exclude the original VBL state owner when installing the replay path and
rebuild presentation separately. Skipping these display calls is not itself a
complete visual implementation.

Chosen hybrid policy: `field_guidance_advance` acknowledges the previous
field's request at the beginning of the next active delivered field, then runs
the native progression. This matches the earliest native one-field screen-swap
handshake and removes delays caused by slow rendering. It intentionally does
not preserve render-dependent waits. Constructors, this field step and world
updates must execute in chronological order, so the release uses the guided
slot that actually exists at that field. Slot-generation/presentation identity
and full scheduler/lifecycle binding are still required.

`field_guidance_prepare` takes hunk 0, an even clone, hunk 4 and the private
pending-byte address in a0/a1/a2/a3. It validates callback and pending-byte
access boundaries before writing; `FG_SIZE` is 308 bytes. The caller owns
initialization, nonoverlap and cache flushing. `field_guidance_step` is the
native-equivalence entry, preserving the caller-supplied pending value.
`field_guidance_advance` is the hybrid entry. Both take the clone in a0, preserve
non-result registers, return 1 if state was evaluated or 0 if inactive, and
apply the native quit-zero/enabled-nonzero gate. Inactive calls do not acknowledge
pending state. Neither entry acknowledges the scheduler or performs drawing.

`tmp/dev/tools/test_field_guidance_c.py` passes 512 native state comparisons
across phase boundaries, pending/hidden/view combinations and guided-slot
values, plus three inactive cases. Reference graphics callbacks are stubbed;
the comparison covers all state writes, with no writes outside the inventoried
state/private byte/stack. Private pending state is independent of native byte
55. Another 220 ordered fields cover slot replacement and release timing with
batches 1/3/10/25. A 72-field hybrid run exactly matches a reference that
acknowledges the native flag before each active field; arbitrary real swap-flag
values do not affect it. Nineteen corrupted patch boundaries reject before
writes (827 helper calls). Installation, graphics reconstruction and complete
weapon/scheduler composition remain pending behind the CUSTOM1 gate.

### Scheduler-bound guidance and actual launch/release composition

`timing-scheduled-guidance.i` binds guidance evaluation to a delivered player
phase. Its 16-byte context contains scheduler/clone pointers, last field,
valid flag and per-call COMMITTED flag. Initialize metadata at epoch start.
`scheduled_guidance_step` takes the context in a0, requires scheduler phase 1
and healthy upstream owners, and rejects a second evaluation of the same
field. Run it before that field's controls and motion, matching the native VBL
ordering relative to new input. It does not acknowledge player/world work.
Return 0/1 retains the guidance inactive/evaluated result; -3 rejects phase or
duplicate use and -1 reports an upstream fault. All non-result registers are
preserved. Explicit lifecycle rebase must also reset this context's metadata.

After evaluation, field/valid/COMMITTED are recorded before the final upstream
check. Thus a fault arriving during state changes returns -1 with COMMITTED=1;
recovery must account for that field instead of reapplying it. Inactive
successful evaluations also count, so later world activation cannot cause an
extra guidance step in the same delivered field.

`tmp/dev/tools/test_scheduled_guidance_c.py` passes 3,840 fields: 240 per run
at 50/60 Hz, guided weapon types 1/3, and batches 1/3/10/25 (22,932 calls).
It connects actual scheduler history, field guidance, world fire flags, native
tick opening and native weapon/actor execution. Constructors now activate the
guidance controller themselves; no synthetic state-5 release is supplied.
The same complete world-memory snapshots and field guidance states result
across batching, despite different live timestamps and screen-swap flags.
PAL launches occur at fields 17/84/167 and releases at 24/91/174; NTSC launches
at 20/100/180 and releases at 27/107/187. Each release is seven delivered fields
after launch, retaining the controller's field-based phase progression.
Every field also attempts a duplicate call and verifies no additional effect.

`test_scheduled_guidance_fault_c.py` passes post-effect producer-fault injection,
retry without reapplication, wrong ready/world phases and a pre-existing
upstream fault (25 calls). These tests use fixed player motion, a slot-5 target
fixture and the previously documented UI/audio stubs. Full player movement,
remaining world damage/scripts, lifecycle rebasing, guidance graphics and live
cross-CPU behavior are not covered. The bridge remains uninstalled; eventual
native integration must exclude the original VBL guidance state owner and
remain behind CUSTOM1 Enhanced framerate.

### Native damage scan and nested hit routine

`timing-world-damage.i` extracts the native +09C5C..+09F72 scan. It redirects
the scan's direct +09E30 RNG call, both +09E2A/+09E56 effect-constructor calls,
and +09E42's nested hit call to prepared deadline-owned routines. The nested
hit extraction contains +07D8A..+07EC8, including the eight-byte table before
its entry: +07DAE indexes this table PC-relatively. Both nested RNG calls
(+07D98/+07DC6) use the same deadline RNG. The native branch order, variable
draw count, resource damage, indicator changes and effects remain intact.

`world_hit_prepare` takes hunk 0, an even clone and deadline RNG in a0/a1/a2.
The clone is 318 bytes; its callable native-ABI entry is `WH_ENTRY` (8), with
a5 pointing to the authoritative player and d0 holding the notification code.
It retains native register clobbers. `world_damage_prepare` takes hunk 0,
clone, deadline RNG, effect clone, hit-clone base and hunk 6 in a0..a5. The
scan clone occupies 794 bytes including its native player binding.
`world_damage_step` takes player/clone in a0/a1, preserves non-result registers
and returns 0/-1. Wrong player binding rejects before effects. Preparation
validates all changed call sites before copying; callers own nonoverlapping
buffers, stable deadline inputs and instruction-cache flushing.

Execute this scan once after world weapons/actors and before scripts and the
periodic tail. The effect constructor must receive committed world heading
through its existing private input. The scan still writes native effect-flash
countdown values 64/128; its field-rate countdown ownership and ordering remain
an integration obligation. No damage, allocation or UI work is rolled back.

`tmp/dev/tools/test_world_damage_c.py` passes 1,024 nested-hit and 128 full-scan
comparisons in both RNG modes, with different live timestamps and renderer
heading but identical private deadline inputs. Complete native-memory state,
ordered callback arguments and blitter writes match. The nested hit draws once
or twice; scans exercise 0/3/4/5/6/16/20/24 draws as paths and effect-pool capacity
vary. Native effect allocation, object bookkeeping, damage-bit selection and
resource updates run. Write tracing allows only native memory, stack and
blitter registers; no unexpected writes occur. Twenty corrupted boundaries
and a mismatched player binding reject without writes (153 helper calls,
plus raw native/clone hit executions).

The scan fixture supplies nearby threats and a zero-result visibility predicate
(+07FA4), with target-marking, notification, digit/indicator and audio UI stubs.
This validates damage arithmetic/order/private inputs, not actual terrain
visibility or rendered UI. Full world composition, countdown migration and
CUSTOM1-gated installation remain pending.
