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
Experimental TIMING_RUNTIME builds now also have arena-backed capture hooks
independent of the diagnostic seed. Those queues remain paused pending native
foreground/lifecycle activation; see the runtime input section below.
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
player operation. Native-loop installation and live gauge validation remain
pending; the cockpit refresh/needle audit below distinguishes drawing caches
from animation.
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
20 NTSC steps give `v0 + 21*A/40`. The initial implementation retained
finer integration, but the subsequent moving-collision gate failed.
The user has since selected native endpoint preservation with responsive
field-rate controls; section C4c/C4e of PERFORMANCE_PLAN.md supersedes
that earlier design choice. The replacement distributes interval-anchored
native motion contributions. The full C4e gate remains unpassed until
that replacement is composed and validated with the world/lifecycle owners.

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
access boundaries before writing; `FG_SIZE` is now 312 bytes, including the
optional retained-presentation pointer. The caller owns
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

### Nonblocking script work with an explicit modal boundary

`timing-world-script.i` splits native +09F74..+0A14C around its +09FAA call
to +08050. The prefix retains location-triggered script activation and the
native write to player 2C. Ordinary script countdown behavior stays native:
nonpositive signed state 53 does nothing; positive state decrements byte 54,
including zero wrapping to FF. A positive state with countdown 1 instead
returns boundary status 2 before decrement or interpreter entry. The prefix
may already have armed state/countdown 1; those writes are authoritative.

This boundary is necessary because +08050 can enter the blocking challenge
screen/input flow and then wait for button release and a new field. States
2/4/5 also lead to the release wait when their countdown expires. The caller
must not acknowledge the world tick or retry its prefix on status 2. A future
lifecycle owner must suspend sampling, run the native interpreter, rebase
elapsed history and deliberately resume/abandon the pending world. The T-74
68060 graphics issue remains deferred; this extraction does not alter the
screen or bypass its behavior.

`world_script_prepare` takes hunk 0, even clone, deadline RNG, hit-clone base
and hunk 6 in a0..a4. It validates the removed call, native countdown entry,
changed RNG/hit calls and copy boundaries before writing. `SC_SIZE` is 472
bytes: prefix plus appended RTS, the native object-update body and player
binding. The body's +0A0EA RNG and +0A0FE hit calls use the same deadline RNG
and nested hit extraction as damage. `world_script_step` takes player/clone
in a0/a1 and returns 0 completed, 2 boundary or -1 wrong binding, preserving
other registers. `world_script_resume` executes only the remaining body after
the owner completed native +08050, without repeating activation/countdown.
Both are authoritative work, not previews. Lifetimes/cache flushing and
once-only scheduling remain caller responsibilities.

`tmp/dev/tools/test_world_script_c.py` passes 1,024 native comparisons: 768
normal-entry cases (148 stop exactly at native +08050 entry) and 256 direct
body continuations. Inputs cover inactive/positive/negative states, countdown
0/1/2/15/255, location-triggered activation, both RNG modes and varied tracking
angles/tick parity. Full native state, callback arguments and RNG order match
with differing live timestamps; fixtures exercise zero or three draws.
Native location detection, object-table loads/stores, heading and movement
arithmetic run. Visibility is a zero-result fixture and notification/resource
UI callbacks are stubbed, as in the damage tests. Write tracing permits only
native memory and stack. Fourteen corrupted boundaries and both entry points'
wrong-player checks reject without writes (1,043 helper calls).

The native blocking interpreter is not exercised by this suite, and no
scheduler/modal continuation owner or gameplay installation has been added.
Those remain necessary before this split is usable in the CUSTOM1 path.


### Post-motion world coordinator (standalone)

`timing-world-body.i` composes the extracted weapons, damage, script and
periodic-tail entries in native +05894 order. `WB_SIZE` is 30 bytes: seven
longword pointers (native player, weapons, damage, scripts, reserves, periodic,
cleanup) followed by a phase word. Initialize phase 0 only when admitting a
new world tick, after opening, commands and player motion. All four embedded
player bindings are checked before effects, including the periodic binding.

`world_body_step` and `world_body_resume` take the context in a0 and preserve
non-result registers. Results are 0 completed, 2 modal boundary, 3 flight ended,
-1 binding/child failure and -3 wrong phase. Phase is 0 ready, 1 awaiting modal
completion, 2 completed, 3 flight ended, or 4 in progress/failed after admission.
Starts require phase 0; resumes require phase 1. Admission sets phase 4 before
any child effects, so unexpected child failure cannot authorize a retry of
already applied effects. A preflight binding failure leaves phase unchanged.

The lifecycle owner must complete native +08050 before calling resume; this
coordinator cannot prove that external precondition. Resume executes only the
script body and tail. It never repeats weapons, damage or script activation.
The caller owns stable prepared clones, context lifetime, lifecycle rebasing
and scheduler acknowledgement. No production hook or automatic reset is added.

`tmp/dev/tools/test_world_body_c.py` compares 512 assembled coordinator cases
against native +05894 (or +09FB0 followed by +058A6 for continuation fixtures).
Results include 432 completed sequences, 72 modal boundaries and eight flight
ends. All 72 actual stopped sequences then resume from their boundary state;
the test clears script state to stand in for interpreter completion and
compares against the native remaining body/tail. It does not execute or validate
the blocking interpreter. Another 128 cases exercise direct continuation.
Full native memory, RNG/callback order, private fire consumption and hardware
writes match, normalizing only deliberately different live timestamp/fire
inputs. Duplicate starts/completions reject without native writes. Each of the
four bad bindings rejects before effects in both entry phases (1,625 helper
calls). Native object/state arithmetic runs; visibility, target selection and
notification/resource/audio UI use the existing explicit test fixtures.

This closes the standalone post-motion ordering gap, not the complete C4e
player/world gate. Opening versus field motion, modal lifecycle ownership,
field-owned countdowns and the CUSTOM1 production installation remain pending.


### Combined whole-tick player/world evidence

`tmp/dev/tools/test_player_world_c.py` links the actual extracted opening,
world motion impulses, split player/ground path and post-motion world body.
The assembled test uses rate 3 (h = 1), not a 50/60 Hz approximation. Its
reference executes native +05640 through +056D8, the native pitch clamp,
+05376 stick/attitude, the unmodified +0937C motion and +05894 world body.
This restores all native motion RNG and contact behavior that earlier
isolated motion comparisons intentionally excluded.

The enhanced side runs opening, captures impulses through deadline RNG,
prepares the player candidate, classifies ground contact, commits motion and
its deferred ground effects, then runs the world body. No native player
motion routine is substituted for the scaled implementation. The test
compares the complete native state window, callback/RNG order, hardware
writes and consumed fire flags, with the existing explicit visibility,
target-selection and UI fixtures. Live timestamps/fire flags deliberately
differ from the private deadline packet. Those inputs are normalized; the
next-y history is checked against the supplied current y because raw input
sampling is outside this test (native +05376 reads but does not update the
previous-y latch). No render or raw command/input decoder runs.

The independent fixture sweep passes 512 cases: 505 ordinary completions,
seven flight ends, 191 ground resets, and zero through three motion RNG
draws. It varies tick parity/wrap, altitude, speed/damage eligibility, controls,
previous y, both RNG modes and fire requests (4,620 helper calls). The
`--sequential` run passes another 512 updates across 32 sequences of up to
16 ticks, retaining player, object, RNG and private motion state between
updates. It has 509 ordinary completions, three flight ends, 294 ground
resets and 3,660 helper calls. A terminal result ends its sequence; the
fixture restarts instead of continuing gameplay after flight end. Neither
run encounters a modal screen; the separate world-body suite covers that
split and continuation contract.

These tests strengthen the h = 1 portion of C4e. They do not establish the
field-rate trajectory bound, physical-integration acceptance decision,
world-deadline contact policy, missed-obstacle behavior, render-derived
flight-end migration or cross-CPU runtime behavior. The order tested here
is the native whole-tick order; choosing where opening and random impulses
belong within a multi-field interval remains an installation requirement.


### Field pitch saturation preserves native held endpoints

Moving-stick measurement exposed a non-rounding handling change. Native
pitch clamps to [-12,20] before subtracting current plus previous nonzero y,
so sustained input reaches -14 or +22. Repeating the same pre-clamp every
field instead limited the scaled path to about -12.1/+20.1 at 60 Hz. The
resulting pitch error fed speed, turning and altitude calculations.

`attitude_pitch_clamp_control` now supplies the combined player path's
pre-clamp. It takes the existing attitude/player pointers and the immutable
control packet in a2. For h=3/rate and delta=-(y+previous_y) when y is nonzero
(or zero otherwise), its fractional pre-clamp limits are
`-12 + min(delta,0)*(1-h)` and `20 + max(delta,0)*(1-h)`.
Adding the subsequent scaled control increment then preserves the native
outward endpoint. Only the outward limit is extended; inward movement does
not jump to a shifted lower/upper limit. Release or reversal restores the
corresponding native pre-clamp limit. World impulses remain unscaled and
follow this clamp as before. This is a saturation correction, not a change
to motion coefficients or displacement order.

The helper compares exact pitch numerators with denominator rate and stores
integer/remainder values only when it clamps. Whole-tick fixture rate 3
still calls the original byte/BMI clamp, including its extreme-byte behavior.
Both ordinary and split player entries use the new helper on their private
candidate. Invalid state/control returns -1 before writes. The original
standalone native clamp remains available for native-equivalence tests.

Validation:

- `test_pitch_control_clamp_c.py`: 13,824 exact integer-model field cases
  (all pitch bytes, all current/previous directions, both field rates and
  remainder extremes), plus 256 comparisons with the original whole-tick
  clamp; 28,674 helper calls. Five additional malformed rate/control/fraction
  cases reject without writes.
- The combined native player/world gate still passes 512 cases with all
  motion RNG paths and 191 ground resets. The split-player regression passes
  4,096 native ground cases, 1,356 ordinary/split field comparisons and its
  three rollback cases after the change.
- `measure_stick_motion_c.py` compares nine held directions, reversal and
  pulse tapes in both flight modes and at 50/60 Hz for ten seconds each,
  sampling at exact whole seconds. It uses the previously native-equivalent
  h=1 player path as reference, excludes world/contact effects and includes
  retained fractions. All held-direction final pitch endpoints now match.

Across these 44 trajectories, the largest measured height difference drops
from 59.1 to 9.6 native units and speed difference from 19.9574 to 5.4055.
These are observed maxima, not accepted global bounds. Reversal retains up
to 1.9 pitch units of transient/history difference, and the pulse tape still
shows roughly 37.04 track units of difference. The two-sample native control
history now advances per field, which changes its temporal response; this
and coupled turning require further analysis. Do not classify those effects
as fixed-point rounding or declare C4e passed. Reports are the ignored
`tmp/dev/tmp/c/stick-motion-before-pitch-fix.json` and
`tmp/dev/tmp/c/stick-motion-measurement.json`. Production remains unchanged.


### Fractional pitch selects the heading branch

Tracing the pulse tape found that integer pitch zero briefly selected hover
while retained pitch was already positive. With nonzero roll, native hover
sets track to heading +/-64 angle units (90 degrees); that unintended early
sideways track then decayed through the bank response. This was a branch
quantization artifact, not a rounding bound on continuous turning.

`kinematics_step_fractional` and `kinematics_prepare_fractional` accept pitch
remainder in d1, with denominator equal to the component field rate. Their
other arguments and candidate layout are unchanged. The original entries
remain zero-fraction wrappers. Combined ordinary and split player entries
pass their retained attitude pitch remainder. Invalid fractions reject
before publication; whole-tick mode requires zero.

The continuous hover interval is (-4,0], extending the native integer
predicate without changing any integer input's result. A positive remainder
at integer pitch 0 selects bank immediately; at integer pitch -4 it selects
hover. For these two crossings only, the private candidate uses representative
pitch 1 or -3 during native stage 0 and the scaled heading step. This keeps
both stages' branch choice and yaw clearing consistent. The true pitch is
restored before lift, speed or height arithmetic, and before publication.
There is no change to the authoritative pitch, native instruction clones,
state layouts or heading-response coefficients. Preparation uses eight
additional temporary stack bytes; C4f still must price the complete path.

`test_fractional_heading_branch_c.py` passes 210 cases across both rates,
seven pitches around the two boundaries, five fraction values and all roll
signs. It checks branch choice through yaw ownership, exact hover heading
and track fractions, restored pitch and unchanged authoritative state. Five
invalid fractions (including a nonzero whole-tick fraction) reject with an
unusable candidate. Combined native player/world comparisons still pass
512 cases; the split-player suite still passes 4,096 native ground cases,
1,356 split/ordinary field steps and three rollback cases.

Remeasuring the same 44 ten-second stick trajectories reduces maximum track
difference from 37.0404 to 13.0155 angle units and heading difference from
16.8267 to 9.4747. In the NTSC pulse fixture, first-second track difference
changes from +28.632 to -4.85; the end-of-tape heading difference changes
from +16.729 to -4.5. Position agreement does not uniformly improve: maximum
x/y differences become 88.46/117.72 native units versus 78.3/52.9 before.
Retain these counterexamples; the measured branch correction does not
establish a full trajectory acceptance bound. Native endpoint integration
and finer integration of the rising/falling roll still produce different
turn paths, and input-history timing remains unresolved. Before/after reports
are `tmp/dev/tmp/c/stick-motion-before-heading-fix.json` and
`tmp/dev/tmp/c/stick-motion-measurement.json`. C4e remains unaccepted and
production timing remains unchanged.


### Preserve the native previous-control time horizon

Native +04E42 copies the preceding decoded y byte to +05524 before the
new control read. The main loop calls that decoder at +05884, once per world
tick; +05376 then reads the saved byte. This is a one-world-tick history,
not a one-VBL history. Using the previous consumed field changed the input
response time and caused the remaining reversal pitch drift.

`timing-control-delay.i` retains a 32-byte stamped direction history. Rate
3 uses one sample, 50 uses 17 fields, and 60 uses 20. PAL rounds the 1/3-second
window upward by 1/150 second (less than one field); it does not accumulate
phase drift. Initialization fills history with the explicit previous-y seed.
`control_delay_step` takes private working state, a field stamp and current y,
returns delayed y/status in d0/d1, and requires consecutive stamps including
32-bit wrap. Duplicate/gap rejection leaves state unchanged. Rebase explicitly
at lifecycle discontinuities; do not silently consume missing input.

`player_step_delayed` in `timing-player-control-delay.i` takes the ordinary
player-step pointers plus delay state in a5 and field stamp in d0. It requires
matching rates, copies player shadow/history, substitutes the delayed y in
the private attitude state, and commits history only after player motion
succeeds. The current y still contributes immediately: the first field's
pitch increment is -3/rate for positive input from neutral history. There is
no 333 ms wait before movement. Whole-tick behavior remains the original
one-sample rule. Caller supplies logical tick parity. This is the continuous
path only; split ground/scheduler publication must still adopt the same
history transaction before production use. Direct player entries remain
available for callers explicitly supplying their own previous-y semantics.

`test_player_delay_c.py` passes 1,080 queue-model samples across three rates
and all initialization directions, 2,160 duplicate/gap rejections including
stamp wrap, 32 whole-tick comparisons, four transactional failure cases and
two first-field response cases (3,337 calls). `measure_delayed_player_c.py`
runs 44 ten-second trajectories through the assembled wrapper; every recorded
sample matches an independent Python delay-window model (25,654 calls).
The reversal fixture ends at native pitch 4.0 exactly in NTSC and 3.96 in PAL,
versus 5.9/5.88 with one-field history. Maximum sampled pitch difference is
0.04 rather than 1.9 units across these tapes. Other maxima are not uniformly
better: height/speed differences are 14.22/8.8051 native units. These are
measurements, not acceptance limits; finer displacement and collision gates
remain unresolved. Reports: `tmp/dev/tmp/c/stick-motion-delayed-y-measurement.json`
and `tmp/dev/tmp/c/stick-motion-delayed-y-assembled.json`. No gameplay hook
or CUSTOM1 behavior changes in this extraction.


### Delayed control history through the ground boundary

`timing-player-boundary-delay.i` adds a split transaction above the same
native-duration input history. Its `PD_SIZE` candidate starts with the full
ordinary PB candidate, so existing deferred ground evaluation uses the same
player/shadow offsets. The tail holds working/base history copies, bindings
to delay/shadow/player and a once-only phase word. No authoritative layout
changes. Caller allocates 428 bytes and keeps all bound state serialized.

`player_boundary_delay_prepare` takes the ordinary prepare arguments plus
delay state in a6 and field stamp in d1 (d0 remains logical world tick).
It copies the player shadow and delay history, obtains the delayed y, and
prepares the split player candidate. It changes no authoritative state.
Ground classification may then edit the PB prefix as before.
`player_boundary_delay_complete` uses the ordinary complete arguments plus
a6 delay state. It checks all three bindings and byte-for-byte unchanged
base history before completing motion. Only success publishes the new
history. A failed completion consumes the transaction and invalidates the
PB candidate, preventing retries even after the caller repairs a binding.
Deferred notification/timer effects still require explicit commit after
successful motion; this adapter does not acknowledge the scheduler.

`test_player_boundary_delay_c.py` passes 1,356 rate-3/PAL/NTSC field steps
against the ordinary delayed player wrapper, including shadow/history
identity and retained authoritative tick. Another 4,096 whole-tick cases
match native clamp, attitude, motion and ground effects: 2,531 ground resets
and 241 notification events. Seven failure paths cover late motion error,
changed history, all three wrong bindings, invalid interval and invalid
packet; each preserves authoritative player/shadow/history and rejects
retry (36,899 calls). Notifications remain stubbed as in the prior native
ground suite. Full scheduler adoption, deadline collision policy and
production installation still remain pending.


### Scheduler adoption of delayed control history

`field_player_prepare_delayed` now binds the delayed ground-compatible
transaction to the existing scheduler bridge. It takes the same arguments
as `field_player_prepare`. Its context extends the original 40 bytes with
an initialized control-delay pointer at `FP_DELAY=40` (44 bytes total), and
its candidate must be `PD_SIZE` rather than `PB_SIZE`. The ordinary entry
retains its original 40-byte contract and never reads the extension.
Both entries share phase, field, command-cutoff and rate validation.

The delayed entry stamps history from the delivered record/scheduler field,
not the world tick or render time. Retained commands still block preparation.
`FP_BOUND=2` selects delayed completion; value 1 remains ordinary completion.
The common completion validates scheduler identity/health, publishes the
player and control history together, marks `FP_COMMITTED`, then acknowledges
the field. Rejection before publication invalidates both candidate phases.
An upstream fault at acknowledgement retains the published history and
counts the applied field, just as it retains committed player motion.
Lifecycle recovery must rebase history explicitly, not replay that field.

`test_field_command_player_delay_c.py` passes 1,920 fields with the actual
clock, field history, dual command readers, mode commands, delayed player
bridge and camera rebuilding. PAL/NTSC batches of 1/3/10/25 produce identical
per-field player/shadow/control-history states and world observations; each
run consumes 240 fields and produces the expected 14/12 world deadlines
(26,207 calls). The world remains an observer fixture, not the full world
body, and ground selection is not exercised in this suite.

`test_field_player_delay_c.py` passes 12 rejection cases plus an injected
producer fault exactly at acknowledgement after publication (155 calls).
These cover retained commands, phase/identity/rate errors, invalid motion,
changed history and stale completion; published history is retained after
the injected fault, and duplicate completion cannot advance it again.
The original entry's 11 rejection cases and post-publication fault test also
remain green (130 calls). Production hooks and lifecycle rebasing are still
pending; this closes the standalone scheduler/control-history hand-off.


### Deadline world commands precede player motion

The native main loop calls +04E3C command decoding at +05884 before +0937C
motion at +0588E. Deferring all world-primary commands until after the final
field's motion would make that motion see stale engine/mode state.
`command_phase_world_before_player` now drains the world reader while the
scheduler is still in player phase, only when `TS_DUE=1`. It requires the
player reader to be drained through the delivered command cutoff first,
retains the existing bounded-drain/error contract, and leaves scheduler
phase and completion counts unchanged. Existing command acknowledgements
make a later post-player drain a no-op for that cutoff.

The delayed scheduler/player entry enforces this ordering: when a world
step is due, it peeks the world reader and rejects preparation with -3 if
commands remain. It applies no commands itself. The caller drains player
commands, drains deadline world-primary commands, then prepares motion.
On nondeadline fields only the player reader must be drained. Retained
lifecycle commands still stop progress for explicit handling. The original
ordinary bridge entry retains its prior contract for comparison fixtures.

`test_command_preplayer_c.py` passes 15 scenarios over queue wrap, four
budgets, future cutoffs, pending player commands, phase/due mismatches,
wrong queue and upstream faults (423 calls). It checks unchanged scheduler
completion counts, retained future commands and no repeated world effects
when draining again before or after player acknowledgement.
`test_field_preplayer_commands_c.py` passes 1,920 delivered fields across
PAL/NTSC batches 1/3/10/25, now including both engine toggles and mode changes
with fuel available. Deadline motion rejects before the world drain; all
batch sizes then produce identical player/shadow/delay state and world
observations (28,335 calls). The delayed bridge's 12 rejection cases and
post-publication fault regression still pass. This fixture has a world
observer; connecting native opening, motion impulses and the complete
post-motion world body remains necessary before gameplay installation.


### Scheduled player plus extracted world integration

`tmp/dev/tools/test_scheduled_world_c.py` replaces the scheduler fixture's
world observer with the extracted native world path. Each delivered field
runs scheduled guidance, decoded controls and command drains, delayed split
player motion and completion. At a due deadline, opening runs before command
drains, then eligible motion impulses run before the final field's motion.
The candidate reaches the ground boundary before publication; deferred ground
effects follow successful motion. Fire preparation, weapons/actors, damage,
scripts and periodic reserves/cleanup then execute before world acknowledgement.

This fixture advances the authoritative tick at the deadline opening and
supplies the upcoming interval parity to earlier fields. It initializes tick
65532 to exercise wrap and periodic boundaries. The private effect heading
is the committed player heading shifted by eight; acceptance of that source
for the relocated render-side effect invocation is still separate. A fixture
caller performs each opening once; a production phase owner must retain that
fact across faults/modal boundaries rather than retrying opening after partial
work. This test does not supply that recovery owner.

Eight runs pass: PAL/NTSC with batches 1/3/10/25, 360 fields per run (2,880
fields and 46,301 helper calls). Every PAL run produces 21 world deadlines,
six launches, 90 active-actor visits and two periodic guard evaluations;
every NTSC run produces 18 deadlines, six launches, 72 actor visits and one
periodic evaluation. Guided release and impact code execute as part of the
composition. Per-field player/shadow/delay states and the complete native
state window at every world deadline match across batch sizes, as do actor
traces and final camera angles. The only normalized native bytes are the
deliberately varied live timestamp and screen-swap flag; private deadline
RNG and guidance acknowledgement remain deterministic.

The fixture retains visibility/target-selection and UI/audio stubs from the
individual native-world tests. It stays airborne and no script modal boundary
is reached. Ground evaluation therefore exercises the airborne path, not
C5's terrain/contact acceptance. VBL countdown ownership, navigation-bearing
display work, actual rendering, modal recovery, cross-CPU runtime and native
main-loop installation remain outstanding. This demonstrates combined
scheduled extraction and batch invariance, not complete C or C4e acceptance.


### Once-only scheduled world opening

`timing-scheduled-world-start.i` binds the extracted opening to a delivered
world deadline. Its 20-byte context contains scheduler/player/opening pointers,
last applied field and valid/committed words. Initialize metadata to zero at
a new lifecycle epoch. `scheduled_world_start(a0=context)` requires player
phase and `TS_DUE=1`, checks upstream health, rejects a duplicate field, then
runs the native opening before commands and motion. It does not acknowledge
player/world completion or attempt to roll back clock/cooldown writes.

After successful opening, FIELD/VALID and the per-call COMMITTED flag are
written before the final upstream check. A fault there returns -1 while
retaining applied-work evidence. A retry cannot advance clock or cooldowns
again, including after the test clears upstream fault flags. Binding failure
leaves opening unapplied. COMMITTED describes only the current call; persistent
FIELD/VALID must be consulted when recovering after a failed retry. Production
recovery must account for applied opening before explicitly rebasing metadata.
This guard does not itself implement modal recovery or complete a world tick.

`test_scheduled_world_start_c.py` passes 960 delivered fields over PAL/NTSC,
batches 1/25 and ordinary/wrapping 32-bit field epochs. It also crosses the
native 16-bit game tick wrap and checks exact cooldown decrements, with seven
PAL or six NTSC deadlines per 120 fields. Wrong phase, nondeadline, upstream
fault and wrong player binding reject without native writes. An injected
fault on the second scheduler check proves retained opening effects, no
scheduler completion count, and rejection of duplicate opening after fault
recovery (5,010 calls).

The combined scheduled player/world fixture now calls this guard in place of
the bare opening helper. A focused rerun passes 1,440 fields at both rates
with batches 1/25 (23,815 calls), retaining the same six launches per run,
90/72 PAL/NTSC actor visits, 21/18 world deadlines and 2/1 periodic checks.
State and traces still match across batch sizes. Other world phases and
lifecycle recovery remain the caller's responsibility.


### Field-owned timer/guidance state

`timing-field-vbl-state.i` composes the three world-written VBL countdowns
with the existing guidance extraction. `field_vbl_state` takes hunk 6 in a0,
hunk 4 in a1 and the prepared guidance clone in a2. It validates the clone's
quit-byte binding before effects. A negative quit byte returns 0 inactive;
otherwise it saturating-decrements +4296 and +42F6, advances guidance, then
saturating-decrements +42F7 and returns 1. Guidance retains its own stricter
quit-zero gate. Other registers are preserved. Native setters remain intact.

`scheduled_field_vbl_state` takes a 24-byte context: scheduler, hunk-6,
hunk-4 and guidance pointers, then last field and valid/committed words.
It replaces `scheduled_guidance_step`, not an additional call alongside it.
The pre/post scheduler checks and persistent field identity prevent duplicate
timer/guidance updates after a producer fault. No field/world acknowledgement
is performed. An explicit lifecycle rebase must initialize metadata.

This extracts state only. Native cosmetic RNG, sound, counters and drawing
are not called. The original VBL decrement owners must be excluded when
installed; cosmetic consumers need coordinated snapshots (some native
amplitude calculations use the pre-decrement value). This is not yet an
installation patch or a complete VBL-state migration.

`test_field_vbl_state_c.py` compares 1,536 cases with native +04B48 through
+04C38 (or its negative-quit skip), covering every byte value in each timer,
zero saturation and quit values 0/1/2/127/128/255. Timer values observed at
guidance entry also match. Cosmetic callbacks and guidance bodies are stubbed
for this arithmetic/order comparison; the separate guidance suites test its
actual transitions. A fresh-CPU fault test uses the real extracted guidance,
injects a producer fault after all updates, and proves timers and guidance
cannot run twice. Binding and wrong-phase cases reject without timer writes.

The combined scheduled player/world fixture now uses this field-state entry.
A 1,440-field PAL/NTSC rerun with batches 1/25 passes with identical native
state (including all three countdown bytes), player history and actor traces
across batches. Launch/actor/periodic counts remain unchanged (23,815 calls).
The focused timer/ordering/fault suite uses 1,551 helper calls.
## Coordinated core timing suspension and resume

`timing-lifecycle.i` adds the core lifecycle operation needed before the
standalone components can be installed. The adapter must exclude the
interrupt producer and both foreground consumers for each entire call.
Bindings must already be initialized, stable and nonoverlapping.

`timing_suspend(a0=TS)` disables the clock and both queues, discards unread
field records with accounting, and retains commands and scheduler phase.
Repeated suspension does not count the same discarded records twice.
It deliberately retains an unfinished player/world phase and its commands:
suspension is not permission to erase partially committed native effects.

`timing_resume(a0=TS, a1=EP, d0=field epoch, d1=command epoch,
d2=previous Y)` requires scheduler phase zero, all three upstream owners
inactive, PAL/NTSC clock rate, and previous Y in -1..1. Invalid requests
return -3 without writes. Valid requests reset endpoint fractions, anchor
and delayed-control history, rebase both queues and the clock, then rebase
the scheduler. Lifetime field/world counts, losses and discarded-work
diagnostics survive. The native player record is not touched.

The first world deadline is 17 new fields after PAL resume or 20 after NTSC
resume. The old phase is counted as discarded clock units. Retained command
slots are counted once using the maximum unread count of the two readers.
Command and field epochs are independent and support unsigned wraparound.

Before resume, the adapter must finish or explicitly resolve delivered
player/world work, commit any pending ground event, and reset the helper
replay caches and presentation metadata. A suspended due world can be
acknowledged after native completion: `scheduler_world_done` counts that
completion once and returns the upstream-inactive error; lifecycle resume
then clears the fault through coordinated rebase. The resume operation
does not run the native modal interpreter, certify its completion, discard
partially committed work, or reset those external helper contexts.

This is a standalone coordination layer, not a production lifecycle hook.
Native map/menu/pause/disk-load entry points and interrupt exclusion remain
to be installed and verified.

The ignored `test_timing_lifecycle_c.py` executes the assembled layer with
the real clock, queues, scheduler and endpoint player in Unicorn: 549 calls
across PAL/NTSC and ordinary/wrapping epochs. Each case starts with seven
accepted fields, ten unread fields, differently advanced command readers
and stale motion fractions. It checks inactive publication, repeat suspend,
atomic rejection of invalid phase/rate/previous-Y/active owners, retained
fault diagnostics, all fresh player steps through the first deadline, and
once-only suspended-world acknowledgement. Resume leaves native player
bytes unchanged. These tests establish core sequencing; they do not
simulate native modal completion or interrupt races.

## Native modal continuation with suspended sampling

`timing-modal.i` connects the core lifecycle to `world_body_resume`.
Its 14-byte context holds scheduler, world-body and native-interpreter
pointers plus phase. Preparation validates the native +08050 entry and
countdown instructions before publishing bindings. Reinitialization is
only for a newly admitted modal operation, never a partial-work retry.

The adapter calls `timing_modal_suspend` with producers excluded after
committing any pending ground event. It requires a due world phase, a world
body stopped at its modal boundary, valid player bindings, positive script
state and countdown one. It disables sampling while preserving the pending
world. The adapter must then restore interrupts before `timing_modal_run`:
the native interpreter waits for a released button and a new field.

Run verifies all sampling owners remain inactive and marks the operation
running before calling native +08050 with the native player in a5. After
return, it runs only the script continuation and world tail, then acknowledges
the world once. Results are 0 completed, 3 flight ended, -1 failure or -3
invalid phase. Sampling stays disabled. The expected inactive-upstream
scheduler fault after acknowledgement is cleared later by coordinated
`timing_resume`, after the adapter has reset helper and presentation state.
Flight-end callers instead follow their mission-exit lifecycle.

Phases are ready (0), suspended (1), interpreter running (2), interpreter
returned/continuation failed (3), completed (4) and flight ended (5).
Duplicate suspension/run rejects. Failure after interpreter entry retains
progress and cannot cause an automatic interpreter retry or world
acknowledgement. This wrapper does not repeat weapons, damage or the
script prefix already applied before the boundary.

The ignored `test_timing_modal_c.py` compares 40 runs against direct native
+08050 followed by the existing script/world continuation: PAL/NTSC,
script states 1..5, prompt versus early-return paths, and periodic
flight-end versus ordinary completion. Native memory, world state, callback
order and field-wait counts match. The interpreter and native continuation
instructions execute; UI callbacks, an Enter input and VBL arrival are
fixtures. This does not validate the rendered T-74 screen, interactive
typing or live interrupt ownership.

The suite also rejects active sampling, stale phases/countdowns, bad player
bindings and duplicate calls without side effects. An injected binding
failure after interpreter entry leaves it called once, with no world
acknowledgement; retry rejects. Four corrupted interpreter signatures reject
without replacing the prepared context. Production hook installation and
reset of the other per-epoch helper contexts remain outstanding.
The assembled 68000 Unicorn suite passes 830 helper calls.

## Assembled foreground field consumer

`timing-flight-consumer.i` replaces the test harness's per-field orchestration
with an assembled foreground owner. It takes a prepared 68-byte context and
a command budget of 1..128 per reader. Context pointers bind the scheduler,
delivered record, field state, world opening, both command readers, control
mode, retained impulses, endpoint/ground operation, scene geometry, world
body, fire, heading, ground notification and timer. All bindings must be
stable, prepared and nonoverlapping.

`timing_flight_consume` runs after `scheduler_next` delivers a record. It
checks the delivered field and command cutoff, decodes controls, applies
field timers/guidance and any due world opening, then drains player commands.
At a deadline it drains world commands before motion, verifies control mode,
and generates the retained native impulse packet. The endpoint/ground step
publishes player motion and acknowledges the player phase. Any published
ground event is committed even when a producer fault arrives after motion.
Due world work then prepares fire/heading, runs geometry and the remaining
world body, and acknowledges completion exactly once.

Command-budget exhaustion (-2) retains the reader phase; resumption does not
repeat field timers or opening. A command lifecycle boundary returns 2 with
the command retained. Other results are 0 field complete, 1 world complete,
3 script modal, 4 flight ended, -1 latched failure and -3 invalid admission.
Modal return retains scheduler world ownership and the world's modal phase
for `timing-modal.i`. The caller handles that lifecycle and later resets the
consumer context; this entry cannot silently admit another field past it.
Flight-end completion acknowledges the world and requires caller exit.

Failures latch rather than retry partially applied effects. Existing child
COMMITTED flags, event state and scheduler counters remain available for
explicit recovery. A successful completed context can admit the next
delivered field; repeated calls on the completed field reject.

`test_flight_consumer_c.py` compares the complete sequence with the existing
independently driven stage fixture. It executes 1,200 fields: one reference
and four consumer runs per display rate, with batch sizes 1, 3, 10 and 25
and one-command budgets forcing continuation. Completed-field player/history,
world memory, callback traces, RNG effects and final camera angles agree
(13,246 helper calls). The comparison samples both paths after due world
effects; pre-world and post-world player bytes are intentionally different.
The existing UI/visibility/target fixtures remain in use.

The separate fault fixture checks invalid admission without effects,
retained lifecycle commands, budget resumption, pending native script-modal
ownership, and a producer fault after due player publication. It verifies
that published ground-event state is consumed, the player step is counted
once, the world remains pending, and subsequent calls cannot replay work.
It also exercises a positive-geometry flight end, checking cleanup and one
world acknowledgement. The fault/exit fixture passes 279 helper calls.
These are assembled 68000 Unicorn checks. The native frame-loop entry,
producer/lifecycle hooks, memory/context initialization and renderer hand-off
are not installed by this change.

## Runtime arena and loader-facing setup

`timing-core.i` provides the shared assembly dependency order. Including it
installs no game hooks. `timing-runtime.i` defines one even, caller-allocated
27,082-byte arena for the clock, history, command queues, endpoint state,
consumer/lifecycle contexts, events, presentation scratch and prepared native
copies. The source sizes determine all offsets; bindings no longer depend
on the test harness's fixed scratch addresses.

`timing_runtime_hunks(a0=first code address, a1=36-byte output)` follows
the valid DOS LoadSeg chain for exactly nine hunks. DOS BPTRs address the
link word; each code address is four bytes later. Null/misaligned first
addresses, early termination, excess hunks and unrepresentable BPTRs reject
without publishing a partial output table. This assumes loader-owned valid
segment memory, not arbitrary pointer probing or executable-version detection.

`timing_runtime_prepare(a0=arena, a1=hunk table, d0=50/60)` prepares all
native copies with their existing signature checks, initializes the contexts
and native bindings, and leaves sampling paused. `RT_READY` becomes one only
after success. Invalid rates leave the arena unchanged. A signature failure
leaves a partial, unusable arena with readiness zero; never execute its
contents. Preparation is for fresh allocations, not recovery over committed
work. Native game memory is not patched or executed during setup.

The caller must allocate nonoverlapping memory, validate the executable,
flush instruction caches after preparation, establish the mission's current
control mode, reset any later lifecycle metadata, and resume at a freshly
sampled epoch before consumer execution. The existing source remains
standalone: no slave allocation, production entry patch or automatic
activation is added here. Those must obey CUSTOM1 **Enhanced framerate**.

`test_timing_runtime_c.py` passes 1,221 assembled 68000 Unicorn helper calls.
It checks loader discovery against the captured DOS chain, malformed-chain
rejection, invalid rates, early/late signature failures, arena canaries and
write confinement during preparation. All native memory remains unchanged
by setup. Four runtime-only consumer runs execute 240 fields across PAL/NTSC
and two arena addresses, with identical player/history trajectories for each
display rate. Native UI/visibility/target callbacks use the established
fixtures during consumption. This verifies relocatable setup and use of
the initialized bindings, not live memory availability, cache behavior or
production lifecycle hooks.

## Experimental slave allocation and LoadSeg setup

The `TIMING_RUNTIME` build flag now includes the core and `timing-slave.i`
in the slave. It is a temporary integration build, not production activation.
Without that flag, ordinary, VERIFY and TIMING_INPUT builds remain byte-for-byte
unchanged. With it, CUSTOM1 **Enhanced framerate** still gates every allocation
and preparation call. Other executable versions and non-game modules do not
allocate this runtime.

The supported gamemule LoadSeg callback prepares timing before the blitter
patches alter source instructions. It discovers the DOS hunk chain, reads
Exec's documented `VBlankFrequency`, accepts 50/60, and allocates 27,082 bytes
using `MEMF_PUBLIC|MEMF_CLEAR`. Display-mode validation at flight activation
remains required; nominal Exec frequency alone is not live cadence evidence.
The arena stays paused. A later supported module load may reuse it only when
the clock and both queues are inactive and no scheduler phase is pending.

`timing_runtime_status` records preparation success (0), invalid chain or
signature (-1), allocation failure (-2), unsupported frequency (-3), or an
active/pending old arena (-4). No flight hooks or consumer execution are
installed, including on setup failure. Future activation must require success
and readiness. The loader's existing cache flush runs after the callback and
covers the copied code, as documented in CACHE_AUDIT.md. When the main program
returns, the allocation is cleared from the slave pointer and freed once.

Integration exposed collisions with the NDK's task/resident size symbols.
The timing constants are now `TC_STATE_SIZE` and `RT_ARENA_SIZE`; their values
and layouts are unchanged. Diagnostic input includes also avoid redefining
history/command symbols when the shared core has already supplied them.

All three experimental slave variants assemble for the 68000. The ignored
`test_timing_slave_c.py` executes the actual slave dispatch/release entries
with simulated Exec allocation/free calls: 15 calls cover disabled CUSTOM1,
other modules/versions, allocation failure, unsupported frequency, paused
reuse, active/pending rejection, PAL/NTSC setup and duplicate release.
Native game memory remains unchanged. The standalone arena/consumer suite
also remains necessary; these checks do not establish live free memory,
cache correctness on hardware, or native flight-loop ownership.

## Runtime-backed native input capture

`timing-live-input.i` now installs the four validated native capture hooks
in experimental TIMING_RUNTIME builds after successful arena preparation.
CUSTOM1 gates installation as well as allocation. Field capture calls the
original sampler before recording its result; mouse, accepted-command and
fire hooks retain the displaced instructions' register/flag behavior.
Command publication and cutoff updates exclude the VBL producer using Exec
Disable/Enable. Native input/FIFO/fire handling still runs.

The arena grows by 88 bytes to 27,170 bytes: a 48-byte capture context plus
a private 40-byte producer sample. Publication copies that sample into the
history ring. `RT_RECORD` remains consumer-owned and cannot be overwritten
by an interrupt while a world tick uses its timestamp/input. The capture
context holds native hunk pointers, queue/sample bindings, command sequence,
raw relative accumulation, fire edges and sampler binding.

Unlike diagnostic capture, runtime capture treats `$7f` as an ordinary
accepted command. It never rearms or resets either queue from a keypress.
Paused field capture does not publish, clears raw deltas, and does not latch
relative-overflow or command faults into inactive history. Mission/modal
activation must still establish synchronized epochs and clear stale producer
accumulation/edges under producer exclusion.

When TIMING_INPUT and TIMING_RUNTIME are both defined, the diagnostic
installer is suppressed so it cannot overwrite the runtime hook sites.
Ordinary diagnostic builds retain their existing capture and rearm behavior.
All sampling queues remain paused after load; no foreground flight loop is
replaced yet. In particular, active-loop installation must also resolve native
FIFO retirement and lifecycle command handling rather than allowing accepted
native commands to accumulate behind the new private readers.

The ignored `test_timing_live_input_c.py` passes 452 native ABI cases over
all CCR combinations, signed mouse extremes, fire edges and sequence wrap.
It verifies complete field payloads, relative-overflow rejection, paused
behavior, ordinary retention of `$7f`, and an untouched consumer record.
Installer checks cover CUSTOM1 off/on, exact four-site patch destinations
and eight altered boundary/signature cases rejected before patching.
The runtime arena suite passes all 1,221 calls after the layout expansion,
and the slave allocation suite still passes its 15 calls.

All normal and experimental build variants assemble for the 68000. Without
TIMING_RUNTIME, ordinary/VERIFY/TIMING_INPUT binaries remain byte-for-byte
unchanged. These are Unicorn and build checks; live interrupt capture and
foreground ownership are not yet validated together.

## Native FIFO retirement under runtime ownership

The native keyboard producer at +03488 appends to a ten-word FIFO at
`a4+$4c68`, whose longword count is at `a4+$4c7e`. The +034C8 hook runs
after count increment and writes the accepted key into its appended slot.
The native +034E8 consumer normally shifts this FIFO. Bypassing that consumer
without retiring slots would eventually stop native key acceptance.

`RT_CAPTURE_OWNER` uses the previously unused capture word at +38:
zero keeps native ownership, one grants runtime ownership. Preparation
clears it. Activation must set it only when the new foreground loop owns
input; modal/pause transitions must restore native ownership with producer
exclusion. The installed experimental path still leaves it zero.

With runtime ownership, successful `commands_publish` and active, unfaulted
field history, `timing_live_command` retires only the just-appended native
entry while still inside its existing Disable/Enable critical section.
It validates the saved slot offset (even, 0..18), native count (1..10),
count/slot relationship and stored key before clearing the slot and
decrementing the count. Earlier native entries remain intact. The private
queue retains the key and sequence for both command readers.

Failed private retention never retires the native key. Invalid native
count/slot state latches both private queue/history faults and leaves the
native entry intact; explicit recovery owns the already retained private
record. Inactive history, native ownership or another owner value do not
alter native FIFO handling. The wrapper still restores the displaced
instructions' registers and CCR, including X.

`test_timing_fifo_owner_c.py` passes 585 checks: all 32 flag combinations
at each native FIFO depth (320 ABI cases), native/paused ownership, invalid
count/slot relationships, private-queue overflow, and 256 accepted keys
through the original +03488 producer with the runtime hook installed.
Both private readers retire records during that stream; the native FIFO
stays empty, while full key/modifier words and sequence numbers match.
This verifies the transfer mechanism, not live activation or modal
transitions. The private command consumers still own exactly-once effects.

## Runtime-wide activation, suspension and script-modal return

`timing-runtime-lifecycle.i` supplies the runtime's complete metadata/ownership
transition around the existing core lifecycle. The native adapter must exclude
both producers and consumers for activation/suspension; the functions do not
change interrupt enablement themselves.

`timing_runtime_activate(a0=arena)` validates readiness, inactive upstream
owners, native FIFO ownership, a resolved scheduler phase, an empty ground
event, PAL/NTSC rate, completed/fresh consumer/world/modal phases, a valid
native FIFO count, and a ready native player. It also checks that the native
input context pointer still names hunk 6. Pending work, failed consumer state,
an ended player or invalid input returns -3 without writes.

After validation, activation discards native menu/pause FIFO entries, counting
them in `RT_NATIVE_DISCARDED` (capture-context longword +0). It resets reader
metadata, once-only helper keys/caches, consumer/modal phases, producer raw
deltas/edges, private records and presentation scratch without rewriting code
or bindings. It reconciles control mode from the native player, samples the
native field counter/current Y and accepted command sequence, rebases the
core, then grants runtime FIFO ownership. Clock/scheduler/loss/discard
diagnostics survive. The arena remains 27,170 bytes.

`timing_runtime_suspend` disables sampling and restores native FIFO ownership,
retaining unfinished scheduler/world work. Repeated suspension does not erase
that work. Fresh activation cannot silently abandon a retained player step,
world tick, command boundary, modal continuation or failed consumer.

For script modals, `timing_runtime_modal_suspend` follows consumer result 3,
suspends through the existing modal coordinator and restores native FIFO
ownership. After interrupts are restored, `timing_runtime_modal_run` executes
the interpreter and continuation. It makes the consumer's final phase agree
with normal completion, flight end or failure. Sampling stays off until
activation; no second world acknowledgement is introduced.

`test_runtime_lifecycle_c.py` passes 36 helper calls covering atomic rejection,
stale metadata/fraction removal, native FIFO accounting, preserved clone code,
input-mode reconciliation and suspension of pending work. The activation-based
arena fixture passes 1,221 calls and 240 consumed fields on PAL/NTSC at two
allocation addresses. A separate 108-call runtime modal fixture consumes a
world deadline, executes native +08050 with UI/VBL fixtures, completes the
world once, reactivates and consumes its first fresh field. These tests do not
replace live interrupt validation. Native flight/menu hooks, retained keyboard
lifecycle-command handling, and VBL presentation coordination remain
necessary before activating the consumer in gameplay.

## Native VBL gameplay ownership switch

Experimental runtime builds install `timing-live-vbl.i` after input capture
installation, behind CUSTOM1. The installer validates all four displaced
instructions and relocated operands before patching any VBL site. The arena
must already be ready. Default builds do not include these hooks.

The byte countdown stores at +04BA8, +04BBA and +04C32 target hunk 6
+4296, +42F6 and +42F7. With `RT_CAPTURE_OWNER=1`, their wrappers compute
the original SUBQ flags but suppress its store. Otherwise they execute the
native decrement. All registers and condition codes match the displaced
instruction, including X; native zero guards remain in place.

The +04C12 guidance call similarly tail-calls native +0A1C8 with native
ownership, or returns without state/display effects under runtime ownership.
Its trampoline preserves entry registers and flags in either path. These
are interrupt-only hooks: reading SR is legal in the native VBL server.
The field consumer already replays the countdowns and extracted guidance
state in their native order.

`test_timing_vbl_handoff_c.py` compares 180 cases across the original VBL,
patched VBL with native ownership, and patched VBL with runtime ownership
followed by field replay. Timer and guidance state agree, and the runtime
VBL makes no writes to those gameplay fields. Cosmetic sound/drawing
callbacks are stubbed explicitly. The slave setup suite still passes all
15 calls, and all three experimental build variants assemble.
`test_timing_live_vbl_c.py` passes 3,274 register/CCR comparisons: all byte
values for each timer, all 32 incoming flag combinations at arithmetic
boundaries, both ownership modes, and the guidance trampoline. It also checks
the four patch destinations, CUSTOM1/readiness gates and 12 corrupted
opcode/operand cases rejected before patching. All three default build
variants remain byte-for-byte unchanged.

This is an ownership mechanism, not gameplay activation. Sampling and
ownership remain off after load. Guidance drawing must be reconstructed
separately, and native audio still reads authoritative timers: cosmetic
snapshots must be coordinated with delayed field consumption. Live
interrupt/foreground validation and native flight/menu hooks remain open.

## Retained guidance hardware-sprite presentation

`timing-guidance-present.i` now reconstructs guidance presentation separately
from state progression. Runtime preparation binds the four removed clone
callbacks to capture helpers. The clone keeps a0 as its base at those sites;
the helpers preserve its registers, resolve the original position/image
tables at the delivered field, and retain the latest request for each of the
two hardware sprites. Capture makes no graphics calls and does not change
additional native gameplay state. A negative image selector hides the sprite
at X=-32 while retaining the base image pointer, matching the native branch.
The reset callback retains hidden requests for both sprites.

Each retained request contains the native viewport, sprite, signed X/Y and
image pointer. A dirty mask permits intermediate requests to be replaced
during catch-up. `guidance_present(a0=context)` applies the dirty requests
through the original MoveSprite/ChangeSprite wrappers, clears their dirty
mask, and returns the number presented. It never advances the guidance
phase, changes eligibility or acknowledges pending state. The caller must
serialize capture and presentation; this is a foreground render entry, not
an interrupt reader of a partially written request.

`guidance_present_init` initializes bindings and two hidden requests.
`guidance_present_bind` validates all four update-only NOP sites before
patching the clone; an already bound or altered clone rejects without
partial patching. Existing LoadSeg cache flushing covers this binding.
Runtime activation resets the retained requests to hidden so a previous
epoch's sprite positions cannot leak into the next one. The arena is now
27,232 bytes: four additional guidance metadata bytes and a 58-byte
presentation context.

`test_guidance_present_c.py` passes 240 native comparisons across phases,
image modes, hidden/view state and pending handshakes. Captured requests
match the original library-call arguments; rendering leaves native gameplay
memory unchanged, repeated clean presentation does nothing, and five fields
without rendering retain the latest request per sprite, including completion
hiding. Runtime preparation still passes 1,221 calls and 240 PAL/NTSC fields
at two allocation addresses; slave setup passes 15 calls. The lifecycle
fixture also checks that activation replaces stale visual requests with
hidden requests while preserving clone code. Eight altered callback sites
reject atomically. All experimental variants build, and all default variants
remain byte-for-byte unchanged.

These comparisons stub the graphics library calls; they do not establish
pixel correctness or live sprite timing. The foreground render handoff must
still invoke this entry. Native VBL guidance stays suppressed only while the
runtime owns it; production timing remains unchanged.

## Runtime backlog delivery and consumer loop

`timing_runtime_batch` now supplies the foreground loop around the existing
scheduler and field consumer. Its arguments are the activated arena in a0,
field budget (1..128) in d0, world budget (1..8) in d1 and command budget per
reader (1..128) in d2. It preserves non-result registers. An idle call takes
one scheduler snapshot; it drains that snapshot in order, including each
due world tick. Producer publications during consumption do not extend it.

Returns are 0 for a drained snapshot, 1 for a command-budget yield, 2 for a
retained lifecycle command, 3 for a script modal, 4 for flight end, -2 for
excess time, -1 for failure and -3 for invalid admission. Calls after 1/2
resume the same delivered field and reader phase. They do not deliver another
field, rerun the field timers or reset the world budget. Lifecycle commands
remain retained until their owner resolves them.

The arena's new `RT_BATCH` word tracks idle, running, command boundary,
script modal, ended, failed and excess states. Modal/end/fault/excess returns
stay latched: another call cannot repeat native effects or quietly open a
new snapshot. Activation resets the batch state only after its existing
pending-work validation succeeds. The arena is now 27,234 bytes.

Excess time is reported without dropping records inside the driver.
The lifecycle owner must suspend, account for discarded history and explicitly
rebase before continuing. A pending delivered field/world still prevents
activation. No render, modal interpreter or native menu runs inside this
entry. A drained snapshot is the handoff point for presentation; command,
modal and end returns require their respective owner.

`test_runtime_batch_c.py` compares 1,200 completed player fields and final
world state against independently delivered scheduler/consumer calls:
PAL/NTSC, single-field execution and batches of 1/3/10/25. Low command budgets
cause 954 resumptions without state differences. Field/world limits stay
latched, command boundaries remain retained, and clearing an upstream fault
does not silently resume a failed batch. The native script-modal fixture
also runs through this entry, completes its world once, reactivates and
consumes the first fresh field (73 calls, 18 fields). Additional checks
publish a field during consumption and verify that it waits for the next
snapshot, reject invalid admission without writes, and repeat a geometry
flight-end result without additional cleanup. Slave setup still passes
15 calls; all three experimental variants assemble.

The native flight call at +0561C enters +0563A after initialization and
returns to +05622 on completion. That is the replacement-loop boundary;
the internal +05830 call enters the old +04288 render-count/interpolation
loop. Neither has been replaced yet. Native menu/pause command handling,
render handoff, excess-time policy and live validation remain required
before this becomes the installed gameplay path.

## Native lifecycle/display command adapter

`timing-boundary-command.i` provides the native command execution boundary
needed by the batch driver's retained-command return. Runtime preparation
validates +04ED4's entry, its nonlocal return at +04EEC and its ordinary RTS
at +05334, then stores the decoder entry in `RT_BOUNDARY`. The arena is now
27,238 bytes.

`boundary_command_step` takes the native player in a0, that four-byte binding
in a1, native hunk 6 input context in a2 and the full accepted command word
in d0. It accepts only the previously inventoried boundary commands and
preserves non-result registers. It returns 0 on normal completion, 4 when
the player has ended the flight, or -3 for a non-boundary key or empty binding.
It does not mask command modifiers.

The wrapper supplies the two return addresses expected by the native
decoder. The direct exit keys discard the inner return before returning
from the command reader. Escape while paused instead first discards the
pause handler's saved sound pointer. Both paths return through the adapter
with the caller's stack intact. Native command effects and the yaw tail
remain in their original order wherever reached.

Enhanced key 12 is retired, as permitted by C7d: it runs only the existing
control tail and never changes the old player speed-toggle flag, render-count
variable or indicator. Other boundary commands execute their native code.
This does not alter default native decoding.

`test_boundary_command_c.py` passes 396 native state/callback comparisons:
eleven native boundary commands, sound on/off, yaw and speed combinations,
immediate/delayed pause release and Escape during pause. It checks stack and
register preservation, six retired-speed cases, seven non-boundary/modifier
rejections, an empty binding, and six corrupted signature cases with no
binding write. UI/audio callbacks are fixtures; this is not live menu or
pause validation. Runtime preparation still passes 1,221 calls and 240
PAL/NTSC fields at two allocation addresses, slave setup passes 15 calls,
and all three experimental variants assemble.

Queue/lifecycle coordination remains the caller's responsibility. Sampling
must be suspended before blocking UI; this adapter neither acknowledges a
command nor rebases a partially delivered field. The current consumer may
already have applied field timers and, on a deadline, world opening before
returning a boundary. Such work must be resolved without replay, and both
command readers must account for the command before a fresh epoch is admitted.
The adapter is prepared but not invoked automatically in gameplay.

## Retiring completed boundary commands through both readers

The command record's previously reserved word at +6 now uses value 1
(`CQ_BOUNDARY_DONE`) to record a lifecycle owner's completed native command.
Newly published records still clear this word. No queue size or arena size
changes are needed.

`boundary_command_mark(a0=queue,a1=original eight-byte player-head record)`
returns 1 on success or -3 on rejection, preserving non-result registers.
It requires a paused, unfaulted queue, the exact unmarked retained player
head, a boundary-class key and valid reader distances. The world reader
must not have passed the player head. All checks precede the only write:
setting the retained slot's marker. Neither cursor nor the caller's private
copy changes. Active, stale, malformed or already marked requests reject.
The lifecycle owner must exclude both readers and mark only after native
execution, retaining its execution phase if marking fails; rejection does
not authorize executing the native key again.

Both command readers recognize this marker only on boundary-class keys.
They skip the native primary and yaw tail, update their completion/accounting
metadata and acknowledge the slot independently. The world reader can still
process older world-primary commands before reaching it. Invalid marker
values or a marker on an ordinary command reject without applying effects
or advancing a cursor. The normal full-record acknowledgement check still
prevents an old unmarked private copy from acknowledging a marked head.

`test_boundary_mark_c.py` passes 216 combinations across all twelve boundary
keys, normal/wrapped cursors, sequence wrap, and world-reader lag up to the
queue's capacity (11,110 calls). It also verifies ten atomic rejection cases
and twelve invalid-marker reader cases. An integrated batch test retains
key 12 on field 2, executes/marks it, resumes that same field and lets both
readers retire it by the first world deadline. All 17 fields complete with
exactly 17 yaw-tail calls: the boundary adds no duplicate tail. An older
world-primary command remains queued until the deadline.

That integrated fixture pauses only the command queue around a nonblocking
retired key; it does not establish full UI pause/rebase behavior. Runtime
preparation still passes its 1,221 calls and 240 PAL/NTSC fields, and all
experimental variants assemble. Production lifecycle coordination remains
pending.

## Retained keyboard boundary suspension and native execution

`timing-runtime-boundary.i` connects boundary-command execution and marking
to the runtime lifecycle. `timing_runtime_boundary_suspend(a0=arena)` must
run with producer/consumers excluded. It requires the batch's retained
player-reader boundary, matching sequence/key and unmarked queue head,
healthy active owners and a ready native binding. All rejection checks
precede writes. On success it retains the full record, suspends private
sampling and returns keyboard ownership to the native code. Unread fields
are discarded with the existing history accounting. The delivered field,
any applied field timers/world opening and pending scheduler phase survive.

`timing_runtime_boundary_run` runs after interrupts are restored. It requires
the suspended boundary and inactive private owners. It sets an executing
phase before entering native UI, then records completed effects before
marking the queue. Success returns 0 or 4 for native flight end. A marking
failure retains an applied/unmarked phase and returns -1: calling again
cannot replay the native command. Invalid admission returns -3 unchanged.
Both normal and exit paths leave sampling off.

The arena now retains an eight-byte command record, phase and result beside
the native binding, for a total of 27,250 bytes. Phase values are ready,
suspended, executing, applied/unmarked, marked, marked/ended and failed.
Fresh activation rejects unresolved execution phases even if other metadata
has been reset; a successful epoch clears completed boundary metadata.

Native keyboard ownership during UI must not unfreeze gameplay. The live
VBL wrappers therefore suppress their three timer stores and guidance call
whenever a retained boundary phase is nonzero, as well as during ordinary
runtime ownership. Native keyboard reads and field counters remain available
to the UI. This keeps the boundary's gameplay state frozen until completion
and rebase are resolved.

`test_runtime_boundary_c.py` exercises ten native cases, before a deadline
and on the first world deadline: retired key 12, pause/resume, Escape during
pause, and both direct exits. Pause uses the actual native FIFO reader, not
a keyboard callback stub. It verifies retained pending work, discarded
unread fields, inactive sampling, single execution, and an injected failure
after native effects that cannot be replayed or bypassed by activation.
Thirteen invalid suspension cases and nine invalid execution admissions
reject without writes.
The existing lifecycle suite still passes 36 calls. VBL tests pass their
3,274 ABI cases plus suppression checks through all six retained boundary
phases, and slave setup passes 15 calls. All experimental variants assemble.

This completes suspension/execution, not pending-field completion. After
the UI returns, the coordinator must finish or explicitly terminate the
retained field/world, account for both command readers and only then admit
a fresh epoch. Native-loop installation and live pause validation remain open.

## Completing or cancelling a retained UI field

`timing_runtime_boundary_finish(a0=arena,d0=command budget)` completes only
the delivered field retained across native UI. It returns 0 complete, 1 for
a command-budget yield, 2 for another keyboard boundary, 3 for a script modal
already suspended, 4 for flight end, -1 for failure or -3 for invalid
admission. Non-result registers are preserved. All returns leave private
sampling inactive and keyboard ownership native.

The helper temporarily activates the existing consumers without delivering
another record or rebasing the clock. The live field and accepted-key adapters
now exclude every retained boundary phase independently of their active
flags. Native sampling/FIFO handling continues, accepted-command sequence
counting continues, and accumulated private mouse deltas are cleared, but no
new fields or commands enter the old epoch. These adapters or external
producer exclusion are a prerequisite for calling the helper.

Budget retries resume the same player/world reader. A second unmarked boundary
in the delivered cutoff can be suspended/executed while remaining paused:
the suspension entry accepts the completed previous boundary and validates
the new retained head without temporarily enabling the queue. A script modal
reached by world completion is admitted and suspended before returning to its
existing interpreter/continuation owner. Normal completion clears the
discarded backlog's snapshot metadata; fresh activation remains explicit.
Unread command-reader debt is accounted by the existing rebase operation.

Native direct exit or Escape during pause follows the original decoder's
return to outer flight cleanup: it skips the remaining motion/world tail.
The helper clears that pending scheduler phase, discards/accountably retires
remaining command debt, and increments `RT_BOUNDARY_ABORTS`. It does not
increment completed player/world counters or run additional world cleanup.
The already applied field timers and world opening are retained. This
four-byte counter survives epoch activation; the arena is 27,254 bytes.
Repetition rejects after the field has been resolved.

`test_runtime_boundary_finish_c.py` compares paused and uninterrupted player
and endpoint state before and on the first deadline for PAL/NTSC. It covers
command-budget retries, two keyboard boundaries in one delivered field,
native pause FIFO consumption, fresh-epoch input acceptance, six native exit
cases, and a script modal reached during completion. All twelve completion
cases pass. Live-input tests still pass 452 ABI cases and additionally prove
that active consumer flags cannot allow publications through any of the six
retained boundary phases. The earlier ten-case suspension/execution and
36-call activation suites still pass. All experimental variants assemble.
An injected post-motion fault preserves the committed step, keeps sampling
off and rejects replay. A separate backlog fixture starts with three
snapshotted fields, pauses on the first, discards the other two and verifies
that only the retained field completes before fresh-epoch input is accepted.
Slave setup still passes 15 calls.

The native flight-loop hook and live lifecycle behavior remain unvalidated;
these are assembled runtime/harness results, not installed production timing.

## Direct native single-frame input publication

`timing_runtime_present_state(a0=arena)` builds the inputs consumed by native
+05C04 without invoking the +04288 render-count/interpolation loop. It requires
an active, healthy runtime with a drained batch, no pending field/world and
no retained UI boundary. It returns 0, -3 for invalid admission or -1 for
invalid camera fractions, preserving non-result registers.

It seeds a private 16-byte instrument buffer to retain the native holes and
externally owned bytes, runs the existing read-only camera/instrument builder,
then applies endpoint fractional camera angles. A private 54-byte scene vector
combines that camera, the six committed object coordinates and the special
object's split coordinate bytes. No native destination is published until
camera validation succeeds. The extra scratch makes the arena 27,324 bytes.

Publication updates hunk 6's render context at +3904, the native scene endpoint
and previous-endpoint buffers, hunk 5's camera-position copy, and the current
instrument/gauge buffers. Instrument copies use bytes because the native
block starts at odd address +157D. Current/previous caches are synchronized
to the published state for subsequent native UI use. The caller must
serialize foreground state and presentation readers during publication.

The entry performs no graphics calls, gameplay updates or RNG draws. It does
not clamp authoritative pitch, advance guidance, acknowledge a tick, clear
the object-change mask or interpolate world objects. Repeated publication is
idempotent. Its fractional camera uses the latest field, not a previous tick.

`test_runtime_present_c.py` passes 256 comparisons against native instrument
building and the actual +04288..+0444A endpoint instructions (drawing stubbed),
plus 256 independently calculated fractional-angle cases. Native write hooks
allow only the listed presentation buffers; player/world state and endpoint
fractions remain unchanged. Invalid admission is atomic, and invalid camera
fractions never publish native inputs. A runtime first-field input changes
the published camera before the first world tick. All experimental variants
assemble.

This establishes native frame inputs, not the frame call or displayed latency.
World-object prediction, elapsed-time instrument slew, render side-effect
isolation and the installed native-loop/frame handoff remain open.

## Render effect construction ownership

`timing-live-render.i` patches the native frame's +05C92 constructor call
only in the experimental runtime behind CUSTOM1. With runtime ownership or
a retained UI boundary it returns without allocation, state changes or RNG
draws. Damage-triggered effects already used the extracted world constructor;
the recurring hit-effect deadline call was added in the field-ownership change
below. Native ownership
tail-calls the original +09B9A constructor. The hook preserves registers and
X without privileged SR reads, including foreground user-mode execution.
The following +0BE5A animation begins with MOVEQ and replaces NZVC; installer
validation checks both calls and that instruction before patching.

`test_timing_live_render_c.py` passes 128 comparisons with the real native
constructor, allocator and RNG across all six-slot occupancy masks and both
replay modes, plus 896 suppression cases and seven signature rejections.
Suppression performs no non-stack state writes or RNG draws. Slave setup
still passes 15 calls. All runtime variants assemble; ordinary, VERIFY and
standalone TIMING_INPUT binaries remain byte-identical after rebuilding.

The combined TIMING_INPUT/TIMING_RUNTIME build omits the unused diagnostic
input recorder and buffer, which otherwise exceed a 68000 branch range.
It uses runtime arena capture and VERIFY frame diagnostics and is identical
to the VERIFY runtime binary; it does not supply the standalone GSIH0002
diagnostic copy. Standalone input diagnostics are unchanged.

The initial hook isolated construction only. The animator audit and subsequent
field-ownership change are described below. Other render writes still require
audit before native flight-loop activation.

## Effect animation changes allocation lifetime

The six unconditional byte decrements at +04C40..+04C5E update hunk 0
+0C724..+0C729 once per native gameplay VBL. The animator at +0BE5A tests
bit 0 of each slot's type byte (hunk 0 +0C6D6 plus slot index). A negative
timer resets to 8 and advances that slot's animation frame (+0C6DC). On
frame 6 it writes lifetime 1 at +0C6D0 plus slot index. The world active-effect
branch at +0C456 decrements that lifetime and clears the shared allocation
bit at +0C464 when it reaches zero. Subsequent effect allocation, including
whether allocation succeeds and consumes RNG, can therefore depend on how
often the renderer calls the animator.

The ignored `audit_render_effect_c.py` executes the actual native six-timer
decrement block, animator and lifetime-release branch. Its single active
effect starts with native constructor values: lifetime 64, type 9, frame 0,
timer 12. At PAL with a three-Hz world, rendering every field releases it at
field 67 (world tick 4); rendering every ten fields releases it at field 84
(world tick 5). Optional score bookkeeping is excluded by the slot's native
flag, and execution stops before unrelated aggregate calculations. This
is a focused ownership counterexample, not a full-game timing result.

C7a must retain field-based countdown semantics while advancing both the
countdowns and animation in consumed-field order, before the corresponding
world work. The native VBL decrements and render animator must be excluded
under runtime ownership and retained UI boundaries, with unchanged baseline
behavior. A whole catch-up batch must not age newly constructed effects using
fields that preceded their construction. The implementation below addresses
this dependency; the constructor hook alone did not solve it.


## Field-owned effects and recurring deadline construction

`field_effects_step` now replays all six wrapping countdown bytes and the
native animation rules once per consumed active field, after the other
field gameplay timers and before world opening/commands/motion. It preserves
registers, performs no drawing or RNG, and retains native signed-byte frame
comparisons and timer reset values. The guidance binding carries the effect
slot-table pointer; FG_SIZE is now 316 bytes.

The experimental VBL patch validates and replaces all six countdown stores
as one span. Native ownership retains their writes and exact final flags;
runtime ownership or a retained UI boundary computes those flags without
stores. The render animator likewise tail-calls native code under native
ownership and skips state updates under runtime/UI ownership. These hooks
remain behind CUSTOM1. The following tracer routine initializes its own
inputs and does not consume animator return flags.

The foreground consumer now explicitly invokes the extracted recurring hit
effect once per world deadline while the hit countdown is nonzero, after
committed player motion and heading publication, before geometry/world work.
It uses the committed player pose and deadline RNG. Damage-triggered effect
calls remain in native damage order. This closes a gap discovered by the
integration fixture: extracting the constructor for damage had not itself
scheduled the renderer's recurring invocation. The constructor is inside
the non-retryable executing phase, so modal continuation does not repeat it.
TF_SIZE is now 76 bytes; epoch reset clears only its metadata, retaining the
new effect/timer bindings. The runtime arena is 27,336 bytes.

Validation in the ignored native-code harness:

- `test_field_effects_c.py`: all 65,536 frame/timer byte pairs, 512 mixed
  active/inactive slot cases, and 7,168 suppressed hook ABI comparisons.
- `test_timing_live_vbl_c.py`: 3,274 existing ABI cases, 30 corrupted-site
  rejections, CUSTOM1 and READY gates, and the complete six-store patch span.
- `test_effect_cadence_c.py`: the prior slot-release counterexample now ends
  at field 67/world tick 4 with no rendering, every-field rendering, or
  rendering every ten fields.
- `test_runtime_effects_c.py`: 960 fields across PAL/NTSC batches of 1, 3,
  10 and 25, comparing per-field slot state, allocation masks and final RNG.
  The first recurring spawn appears on the first deadline, and its timer
  first decrements on the following field, including catch-up batches.
- Existing batch tests pass 1,200 fields and 954 command-budget yields;
  retained UI completion passes twelve cases, lifecycle reset 36 calls and
  slave setup 15 calls. Constructor ownership checks still pass 128 native
  and 896 suppressed cases. The field timer regression passes 1,536 cases.

All runtime build variants assemble. Default, VERIFY and standalone input
builds remain byte-identical. These are assembled/native-harness results;
full native-loop installation, other render-state isolation and live CPU
validation remain open.


## Map coordinates follow consumed player fields

The +0468C panel dispatcher calls +0489A in map-panel mode 1. Its prefix
increments hunk 5 +48, compares the new word against 8, and calls +0475A only
when unsigned-below. That coordinate routine clears the same counter at
+04840. Consequently the normal zero-start path refreshes on every map frame,
not every eighth frame. Counters initially 7 or above skip refresh until
word wrap; this odd native behavior is preserved when enhanced ownership
is inactive.

The foreground consumer now calls the native coordinate-only +0475A entry
once after each successful committed player field when panel mode is 1.
Runtime preparation validates its player X/Y bindings and return boundary.
Its eight-byte entry/mode binding extends TF_SIZE to 84 and the runtime arena
to 27,344 bytes; epoch reset retains those pointers. The routine computes
clamped map and rotor-sprite positions, sets the existing two-buffer dirty
count when needed and updates cached coordinates. It makes no OS calls.

`timing-live-map.i` validates the complete +0489A..+048B6 prefix and keeps a
relocated native copy. Native ownership executes that copy, including the
original counter behavior and sprite update. Runtime ownership or a retained
UI boundary skips coordinate mutation and calls the sprite update directly.
The +048B6 drawing path and its buffer-indexed dirty-count decrement remain
native. The installer is experimental and CUSTOM1-gated; installed clones
are covered by the existing LoadSeg cache flush.

`test_timing_live_map_c.py` passes 288 native register/CCR/state comparisons,
including counter wrap and foreground user mode, 2,016 runtime/retained-UI
exclusion cases, and 14 corrupted-prefix rejections. The fixture stubs the
sprite update and verifies exactly one call in every lane; it does not claim
rendered sprite equality. `test_runtime_map_c.py` passes 800 moving-player
fields across PAL/NTSC batches of 1, 3, 10 and 25, comparing each field's
committed pose and map outputs; three other panel modes leave those outputs
untouched. Retained UI completion passes twelve cases, lifecycle reset
36 calls and slave setup 15 calls. All runtime variants assemble, and
ordinary, VERIFY and standalone input binaries remain byte-identical.

The targeting path in the same panel dispatcher is separate and remains an
integration blocker: +0A450 collects projected candidates, +0A58C commits
selection, and +0A6A2 tests a rendered pixel through +0825E. The existing
private geometry check deliberately disables candidate collection. Moving
map-coordinate refresh does not isolate target acquisition or make it
independent of rendering.


## Private target selection with explicit visibility samples

Native +0A450 appends up to five projected candidates. Selection at +0A58C
searches for the previous identity/subtype, tests candidate pixels through
+0A6A2, and scans alternatives in native order. The pixel predicate rejects
colors equal to either palette byte +18/+19 in hunk 6 +16DC, using the
alternate palette at +17DC when player byte +16 is nonzero. It is a color
test, not an identity or depth-buffer test. Substituting a generic line-of-
sight check would therefore need separate equivalence evidence.

`timing-target-select.i` copies +0A58C..+0A6E4 and relocates every HUNK operand
into a private workspace. Its 168-byte native-shaped target state mirrors
hunk 0 +0A99E..+0AA46:

| State offset | Native content |
| --- | --- |
| +00 | Selection status byte |
| +02 | Candidate count word, 0..5 |
| +04/+06 | Selected identity/subtype words |
| +08 | Five descriptor offsets |
| +12 | Five 18-byte descriptors |
| +6C/+76 | Five identity/subtype words |
| +80/+8A | Five projected X/Y words |
| +94 | Five model pointers |

Offsets in this table are hexadecimal. The native selector copies the
chosen descriptor, projected position and model pointer into the first
entries and clears candidate count, preserving the original search and
no-target behavior. Model pointers are carried as data, not dereferenced
by this selector.

`target_select_prepare(a0=h0,a1=h6,a2=workspace)` checks all 30 relocations
and routine boundaries before writing. It creates a 546-byte workspace;
state starts empty. `target_select_step(a0=workspace,a1=five pixel bytes,
a2=two rejected colors)` validates count and descriptor offsets before any
writes, snapshots the explicit inputs, and executes the copied selector.
Its ReadPixel replacement indexes the supplied samples by candidate cursor.
The private palette uses the two caller-selected colors, so the selector
never reads a live palette, bitmap, player mode, native target state or RNG.
Both entries preserve non-result registers. Invalid state returns -3
atomically; invalid native signatures return -1 before destination writes.

The caller must collect candidates and sample pixels from the same committed
world view; samples from a prior displayed or predicted frame are not valid.
This helper does not acquire visibility, collect candidates, publish a lock,
or install a native target hook. It is included for standalone/runtime
assembly but is not bound into the runtime arena or world sequence yet.

`test_target_select_c.py` compares 2,048 cases against the original selector,
with a deliberately explicit pixel-input stub in the native reference. It
covers all 256 pixel colors in both palette modes, counts 0..5, selection
states, duplicate/negative identities, descriptor permutations and native
query order. Private state matches native output, with no native writes.
It also checks 62 corrupt-signature cases and five atomic invalid-state
rejections. These results prove selection arithmetic/order given matching
pixel inputs, not visibility equivalence or correct targeting in live play.
All runtime variants assemble; ordinary, VERIFY and standalone input
binaries remain byte-identical.


## Private projection and candidate collection

`timing-target-collect.i` extracts +0A450..+0A58C. All 31 HUNK relocations are
validated before the 316-byte clone is written. Target writes are redirected
into WT_STATE; object identity, cell, transformed depth and projected X/Y
reads use private scene scratch. Viewport bounds, targeting limits and native
model data remain stable shared reads. The special model pointer at +05A24
remains a native pointer because it is identity/data carried into target state,
not a private code entry.

`scene_target_prepare` creates a projection-enabled variant of the existing
private scene workspace. It restores native vertex transformation/projection
at +06642 and native point-object projection at +06372. Both candidate-call
sites (+06356/+063D4) use the private collector. Polygon rasterization remains
stopped at +063F8; point-object color, pixel and glyph drawing calls are
removed after signature validation. The native point clipping predicate is
retained and only reads viewport bounds. This variant has an eight-byte
binding suffix and a 168-byte selection snapshot, for SCT_SIZE = 8,040 bytes,
plus the separate 546-byte target workspace and 316-byte collector clone.

`scene_target_step(a0=SCT,a1=committed camera,a2=committed object coordinates)`
validates descriptor offsets, clears the previous candidate count, and runs
the private scene traversal with full native projection. It snapshots target
state after +060A8, at the native +05C78 selection boundary, before +06224's
projectile overlay. The overlay still runs for the final flight-end plane
flag, but its target writes are discarded in favor of the selection snapshot.
Previous selection identity/status and descriptor-offset layout are retained.
The entry only writes private scene/target/stack state.
It does not sample pixels or decide which projected candidates are visible.
The caller must keep shared model/viewport/targeting inputs stable and flush
the prepared code before execution. Failed preparation is not callable.

`test_target_collect_prepare_c.py` verifies all relocation destinations,
64 corrupted collector signatures and twelve corrupted drawing-call sites.
`test_target_collect_c.py` passes 1,536 native comparisons covering projection
bounds, targeting limits, identity matches, player exclusion and counts 0..5:
274 cases append and 256 exercise a full list. Candidate descriptors, screen
coordinates and model pointers match, with no native writes.

`test_scene_target_c.py` passes 48 views spanning three positions, two heights
and eight headings. Six views collect a candidate; counts are zero or one
in this scene fixture. Candidate state at the pre-overlay selection boundary and final flight-end
plane flags match native geometry/collection, and reused workspaces produce
the same results.
Three invalid descriptor layouts reject without changing either workspace.
The reference and private lanes have the same explicit rasterization
omissions. This distinction matters: equal candidates do not establish equal
visibility colors. The write monitor allows only private scene/target/stack
writes. An initial harness slowdown was traced to regex symbol lookup on
every memory write; caching that lookup allowed the full test to finish
without reducing coverage.

All runtime variants assemble; ordinary, VERIFY and standalone input builds
remain byte-identical. These helpers remain unbound from the runtime pending
committed-view pixel acquisition and target publication/exclusion work.


## Native drawing-pass ordering audit

A native +05C04 frame executes +060A8, then +0468C (whose first call is target
selection +0A58C), then +06224's projectile overlay, HUD and effects. Candidate
state for selection must therefore be retained before the overlay, even
when a full private traversal also needs the later flight-end result. A
late-overlay injection test changes candidate scratch and the plane flag:
`scene_target_step` retains the earlier candidates while returning the later
plane flag. The original full-traversal candidate snapshot was corrected to
respect this boundary before runtime adoption.

The ignored `audit_frame_writes_c.py` now executes the complete native frame
in Unicorn to inventory CPU writes. It completes with 2,386 distinct
PC/address/size write sites in the flight snapshot. Display swapping and the
already-extracted effect constructor/animator are stubbed; ReadPixel returns
an explicit fixture value and blitter DMA is not emulated. This is write-path
evidence only, not a pixel-correctness or hardware result. It identifies the
native raster prefix +05C04..+05C78 as the point at which a committed-view
visibility pass can stop before panel/HUD/display work. The bitmap binding
entry at +084E2 selects the current drawing buffer and writes hunk 6 +47C4.
`timing-visibility-raster.i` now extracts this prefix, retaining its absolute
native bindings and appending the native register restore/return. Preparation
validates all 14 relocation bindings and the native save/restore boundaries
before changing its 298-byte workspace. It remains unbound from the runtime.

`visibility_raster_step` takes a committed camera and object vector. It borrows
the native target block from the supplied private selection state, clears the
candidate count, builds the scene vector and executes the prefix. It waits for
the blitter before retaining candidates and restoring the native target block.
It snapshots the two palette rejection colors for the current player mode,
then uses native ReadPixel to sample each collected candidate's projected
coordinates into the private selector's indexed pixel array. It does not
perform selection, publish a lock, draw overlays or swap buffers. The caller
can pass those pixels/colors to `target_select_step` separately.

This is a foreground-only hardware drawing operation, not a pure geometry
helper: it changes native raster scratch, the selected drawing bitmap and
blitter registers. It requires exclusive ownership of drawing and native
target access. Future renderer suppression must explicitly permit collection
during this world pass. The current runtime does not call it, and no native
target hook is installed by this extraction. Its scratch changes must be
overwritten by the presentation view before the next displayed frame.

The ignored `test_visibility_raster_c.py` compares 48 views (three positions,
two heights, eight headings) with the original prefix. Candidate state and
the native-memory/custom-register write results match, with native target
state restored and all non-result registers preserved. Six views produce a
candidate. Additional post-collection injections exercise counts zero through
five and every indexed sample slot; explicit coordinate-derived pixel values
verify sampling order. Both palette modes are exercised. All 33 altered
signature words reject setup without workspace writes, and three invalid
descriptor offsets reject execution before native/private state writes.

Unicorn does not emulate blitter DMA: these results validate CPU execution and
sample acquisition plumbing, not rendered pixels. Hardware pixel validation,
cost measurements, world ownership and target publication/exclusion remain
open. Candidate selection must not fall back to pixels from a previous or
predicted displayed frame. All three experimental runtime variants assemble;
ordinary builds do not include this helper.

### Live visibility probe: debugger-write fixture rejected

Two isolated headless 68020/PAL sessions reached the cockpit using the shared
native FS-UAE and its checked mouse/input harness. Neither supplies a pixel
comparison result. The first stopped on an incorrect workspace-discovery
assumption: the loaded slave does not have a normal LoadSeg size header at
the assumed position. The second located the diagnostic workspace but could
not execute the intended redirected call.

Inspection of the shared build's `barto_gdbserver.cpp` confirms read handlers
for registers/memory (`g`, `p`, `m`) and no guest-write handlers (`G`, `P`,
`M`, `X`). Thus debugger assignments and binary restores cannot establish the
test state. This agrees with AmigaXDev's new-game playbook requirement to
compile pixel-twin stimuli into the guest. GDB also names the status register
`$ps`; `$sr` is not an appropriate control for this fixture. The ignored
`live_visibility_c.py` prototype now rejects execution explicitly so it cannot
accidentally be counted as validation. Both test-owned emulator sessions and
their debuggers have exited; unrelated sessions were left alone.

The next pixel test must use a compiled diagnostic slave: prepare workspaces
before patching, retain the native drawing-buffer contents, run the original
prefix and extracted pass from identical scene/buffer state, and publish
candidate/pixel/bitmap comparisons for read-only debugger inspection. The
native prefix remains the reference, with actual blitter DMA enabled. Do not
enable runtime visibility ownership on the strength of the Unicorn checks or
these unsuccessful live probes.

### Compiled visibility twin: PAL pixels pass on 68000/020/060

The ignored harness now supplies `tools/visibility_probe_c.i`,
`tools/build_visibility_probe_c.sh` and `tools/run_visibility_probe_c.py`.
The builder derives a diagnostic slave from the current source; it does not
change the distributed slave. Preparation runs before patching, captures an
independent exact copy of the native +05C04..+05C78 prefix, and installs a
diagnostic entry at the panel boundary. A 132,000-byte allocation holds the
two packed bitmap snapshots and per-view records. The test owns its session
until termination: interrupts are disabled, DMA continues, and no native
gameplay resumes after the result loop. All stimuli execute in the guest;
debugger access only reads memory and advances emulated fields.

Each view starts with an explicit camera/object vector, zero candidate count
and a valid descriptor layout. The native prefix and extracted pass receive
the same initial bitmap contents, restored between executions. The probe
compares all 168 candidate bytes, six indexed sample bytes including unused
zeros, and every byte of all five 8,000-byte bitplanes. It retains the native
output and records; the host independently decodes the final view's sampled
colors from the saved plane bits. The native reference uses the existing
CUSTOM1-enabled blitter fixes, as does the extracted pass.

Fixtures use camera XY `$7FFF/$7FFF`, player-equivalent height 512 (camera
height 536), eight headings spaced by 32 native angle units, six nearby
object positions and the nearby special object. Each heading runs in both
palette modes. All 16 views passed on each of:

- `a500-fast`: 68000, PAL;
- `a1200-fast`: 68EC020, PAL;
- `a1200-060`: 68060-NOMMU at 50 MHz, PAL, data cache enabled.

Each CPU produced ten nonempty views, with candidate counts 0..4. Counts and
sampled colors agree across CPUs. The guest comparisons cover 640,000 bitmap
bytes per CPU, 1,920,000 in total. A separate `VP_SABOTAGE=1` 68020 run flips
one saved reference byte; it stops with bitmap-mismatch status -7 before
completing any view. Thus a mismatching plane does not accidentally pass.

Results are retained under `tmp/dev/tmp/c/visibility-probe-a500-fast-complete`,
`visibility-probe-a1200-fast-modes`, `visibility-probe-a1200-060-modes` and
`visibility-probe-sabotage`. An earlier eight-view 020 probe also passed.
The first 000 driver incorrectly treated the route's duration as the test's
duration and exited while the guest was still working after eight views.
The corrected driver polls the same live session until an explicit success
or failure, and its replacement run completed all 16. Register diagnostics
flush GDB's cache after monitor-driven execution. The reproducible normal
probe slave SHA-256 is
`481b5ed3945414b3970f7cb72ddb8f5a75a5ccdc52da3de1743d735a29e9a8c4`.

This proves the raster extraction and pixel acquisition in these authored
PAL fixtures, not full world-state equality, live player responsiveness or
production lifecycle behavior. It does not price the extra world-tick drawing
pass: snapshot copying and comparisons dominate parts of the probe, so its
overall duration is not a renderer benchmark. Cost measurements, NTSC/wider
scene coverage, world ownership, selection/publication and exclusion of
native render target writes remain open. Runtime activation is unchanged.

### Isolated visibility cost with a calibrated guest timer

`VP_TIMING=1 bash tmp/dev/tools/build_visibility_probe_c.sh` builds a separate
`visibility-timing.slave`. Its guest probe cascades CIAB timer B from timer A
to form a 32-bit E-clock downcounter. This is diagnostic-only: interrupts are
already disabled and the test never resumes gameplay. Timer mode constants
follow the NDK `hardware/cia.i`. Ten video-field edges calibrate the counter;
an empty start/stop measures the instrumentation floor. Calibration gives
142,080 E-clocks on the 000 and 142,086 on the 020/060, crossing two low-word
underflows. Empty measurements are six E-clocks on the 000 and one on the
020/060. Raw readings and field-normalized results remain in the reports.

The timed native span is the exact drawing prefix plus its final blitter
wait. The extracted span is the complete `visibility_raster_step`, including
scene construction, target-state borrowing/restoration, the drawing prefix,
the wait and pixel sampling. Snapshot copies, equality checks and fixture
setup are outside both spans. All 16 bitmap/candidate/pixel comparisons still
pass in each timed run.

Times below subtract the empty measurement and convert calibrated fields
using nominal PAL 50 Hz. They are deliberately rounded; the beam phase and
chip-bus contention differ between the paired executions.

| Setup | Native prefix mean | Visibility mean | Visibility range | Three visibility calls/s |
| --- | ---: | ---: | ---: | ---: |
| 68000 (`a500-fast`) | 69.6 ms | 71.2 ms | 53.5–84.6 ms | 21.4% of elapsed time |
| 68EC020 (`a1200-fast`) | 32.0 ms | 32.4 ms | 25.5–37.0 ms | 9.7% |
| 68060-NOMMU, 50 MHz | 22.0 ms | 22.1 ms | 19.9–26.8 ms | 6.6% |

The renderer remains a substantial cost on faster CPUs. This is elapsed
emulated time including blitter waits, not CPU-only instruction cost. The
difference between the two columns is not a reliable standalone wrapper
overhead measurement because of the differing bus phase. These are sixteen
authored samples per setup, not worst-case bounds or a full-game benchmark.
VBL/input work, field motion, world logic, overlays and displayed frames are
not charged to this isolated pass.

The measured pass fits inside one 333 ms world interval in these fixtures,
so proceeding with once-per-world-tick integration is reasonable; it must
not be run per consumed field. Whole-game rate/catch-up tests still decide
whether the combined budget is acceptable, especially on the 68000. Reusing
pixels from a previous/predicted display is not an acceptable shortcut.

Reports: `tmp/dev/tmp/c/visibility-timing-a500-fast/result.json`,
`visibility-timing-020/result.json`, and `visibility-timing-a1200-060/result.json`.
The timed slave SHA-256 is
`c011a954278eff3e9b618aaad52c2246ec1789a2f68a8a990979a4ec43ccacbe`.
World-owned selection/publication, native-render write exclusion and runtime
activation are still pending. These measurements do not complete C9.

## World-owned target publication and native render guards

The experimental runtime now prepares the raster and private selector in its
arena and binds `timing_runtime_target` to the field consumer. `TF_SIZE` is
92 bytes and `RT_ARENA_SIZE` is 28,202 bytes. After committed field motion,
the deadline path invokes visibility/selection before committed geometry and
weapons, matching the native selection-before-post-motion-world ordering.
Ordinary non-deadline fields do not call it.

The callback requires scheduler state 2 (world pending), an executing field
consumer, a matching field stamp and healthy active scheduler owners. It
seeds its private selector from the current native target block, preserving
changes made by native world commands, and builds the camera from committed
player state. The raster pass collects candidates and pixel samples; the
private selector then publishes the complete 168-byte native target block.
It does not draw the panel/HUD, swap buffers, acknowledge the deadline or
advance world logic itself. Native drawing scratch is left for the following
presentation publisher to rebuild.

Target phase 0 is fresh, 1 collecting, 2 published, 3 failed. A field stamp
rejects a second execution for the same deadline. Failure cannot silently
retry; the consumer latches its fault. Normal activation rejects unfinished
or failed target work and clears completed target metadata for the new epoch.
The activation test caught an initial state-1 admission error: committed
player motion has already advanced the scheduler to state 2. This was fixed
before accepting the integration.

`timing_render_install` validates and patches the collector calls at +06356
and +063D4 and the selector call at +0468C, behind the existing CUSTOM1 gate.
Native ownership tail-calls the original entries. Enhanced drawing skips
both mutations; collection is permitted only while the world callback's
target phase is 1. The following native instructions overwrite the skipped
flags and reload drawing inputs. The target-panel routine writes render/UI
scratch beyond the target block; it is not the selector.

Retained UI completion is a deliberate exception to ordinary input ownership:
`timing_runtime_boundary_finish` resumes the held consumer with boundary phase
4 and native input ownership, while its producers remain excluded. The world
callback and collector allow precisely that combination. Other UI phases
still suppress target writes, as does phase 4 outside an active world pass.
The first deadline-completion test failed without this exception; after the
fix all twelve normal/nested/manual-exit cases pass, with paused and
uninterrupted completion states equal.

Validation in the ignored harness:

- `test_runtime_target_c.py`: 16 native prefix/selector comparisons with
  explicit pixel values, full target publication equality, register
  preservation, 16 duplicate-field rejections and atomic invalid-descriptor
  rejection. This is instruction/ownership evidence, not a DMA test.
- `test_target_render_guards_c.py`: 448 owner/boundary/target-phase/CCR cases,
  checking exact native permission and preservation when calls are skipped.
- `test_timing_live_render_c.py`: original effect behavior still matches in
  128 cases; 896 suppressed cases have no native writes/RNG; all 16 altered
  installer signatures reject before patching.
- `test_target_deadline_order_c.py`: 600 fields over PAL/NTSC and three batch
  sizes establish committed motion -> visibility -> weapons order, exactly
  once per deadline.
- `test_runtime_batch_c.py`: the real callback runs over 1,200 fields across
  ten PAL/NTSC batching configurations, including 954 command-budget yields,
  with equal endpoint state and latched limits. Unicorn has no blitter; this
  checks composition/control flow, not picture correctness.
- `test_runtime_activation_c.py`: two field rates and two arena locations
  complete 240 fields with the real callback, reject collecting/failed target
  epochs, and reset published target stamps on activation.

The compiled `VP_OWNER=1` guest probe compares native selection against the
actual runtime callback in world-pending state. It then invokes render guards,
rejects a duplicate callback and compares the native published block, private
selection, pixel array and all five real bitplanes. Sixteen PAL views pass on
68000/020/060, with twelve nonempty collection views per CPU. Selected status,
identity/subtype and sampled colors agree across the three CPUs. Counts in
the retained rows are zero after selection, as required by the native code;
they are not a claim that collection was empty. Results are in
`tmp/dev/tmp/c/visibility-owner-{a500-fast,a1200-fast,a1200-060}-phase2`.
A final `VP_RETAINED=1` 020 probe runs eight ordinary views and eight views
with boundary phase 4/native input ownership, using the same active retained
consumer state. All sixteen native-selection, pixel and bitmap comparisons
pass; its results are in `visibility-owner-retained-020`. The retained probe
slave SHA-256 is
`ee40a2d6503be713c19f4ed856187ce4bb20b49eb15efc15e2daaad43d86eda3`.

All runtime variants assemble. Native flight-loop activation is still absent,
so the ordinary build and default-off behavior remain unchanged. The target
display currently reads the last committed selection; adapting its projected
descriptor/box to the latest presentation camera without changing the world
selection remains open. Full renderer state isolation, remaining instrument
timers, live gauge validation, prediction,
whole-game timing and trajectory acceptance also remain open.

### Field-clocked bar gauges (C4g, experimental runtime)

`timing-field-gauges.i` separates the animation state from the native painter's
bitmap cache. Its reference cadence is one native +0ADB6 draw per video field,
alternating the two buffers. Seven private pairs of byte heights preserve the
native signed-byte comparison, one-pixel step and immediate-fill target bit.
The next virtual slot advances once per consumed field regardless of actual
render frequency; this is a field cadence, not the 3 Hz world cadence.

`gauge_field_init` seeds the private heights from the two native cache bytes
in each 12-byte descriptor at hunk 6 +09BC. `gauge_field_step` takes seven raw
instrument targets and advances one virtual slot. `gauge_field_targets`
encodes the most recently advanced slot as immediate-fill native targets,
so a later draw can repair its selected physical bitmap completely. Scales
1..32 cover the native values 18, 22 and 27; every legal height is encodable.
Invalid phase, scale or height rejects before publishing any output byte.
The private helper never writes native bitmap caches or draws pixels.

The ignored `test_field_gauges_c.py` compares 2,000 field steps directly with
native +0ADB6, using both starting slots and actual render intervals of
1, 3, 10 and 25 fields. It checks 738 skipped-draw catch-ups, all 528 legal
scale/height pairs, register preservation and 12 atomic rejections. The native
pixel writer is stubbed in this test: these are state/drawing-cache checks,
not visual proof. The experimental runtime slave assembles for the 68000.

The runtime now binds `timing_runtime_gauges` after each consumed field's
player motion and map-coordinate refresh, before any world visibility/weapons
work. It rebuilds raw instruments from that field's player state into private
scratch, then advances the virtual buffer slot once. Field stamps reject a
replay; an applying stamp cannot cross activation. World-body changes later
in that field are reflected by the next field's gauge update. No native state
is written by this callback. It also accepts the explicit retained-UI phase-4
completion path, where input ownership remains native during the retained
field. `TF_SIZE` is now 100 bytes and the runtime arena is 28,260 bytes.

Preparation and normal activation seed heights from the actual bitmap caches
and start with the currently selected native buffer slot. Resuming an epoch
therefore starts from the existing drawn state; it does not animate time spent
in menus or paused UI. Map/hidden-cockpit fields still advance the virtual
heights while the physical caches remain untouched until drawing.

The CUSTOM1-gated `timing_gauges_install` validates the native prefix and
patches +0ADB6. Before runtime ownership it executes the exact displaced
prefix and continues at +0ADC0. During enhanced ownership or a retained UI,
`timing_runtime_gauge_draw` temporarily substitutes encoded targets, executes
the original painter, and restores all seven raw target bytes. Bytes 4 and 6
are owned by other native code and must never retain catch-up codes. Native
+0ADB6 still owns both physical bitmap cache bytes; repeated draws neither
advance private animation nor change raw targets. Calls are serialized with
foreground consumption, as with other presentation helpers.

Additional ignored harness checks:

- `test_runtime_gauges_c.py`: 800 consumed fields at PAL/NTSC rates with batch
  sizes 1/3/10/25 and command-budget yields; identical final gauge/player state,
  296 draws plus 296 repeated draws, raw targets restored on every draw.
- `test_timing_live_gauges_c.py`: 64 exact native register/CCR/cache comparisons,
  448 enhanced/retained-UI drawing cases, eight corrupt-prefix rejections,
  CUSTOM1-off no patch, invalid READY rejection.
- `test_runtime_activation_c.py`: rejects applying gauge state, resets stamps
  and reseeds both buffers; existing 240-field/two-location checks pass.
- `test_runtime_boundary_finish_c.py`: twelve retained completion/exit/modal
  cases pass, including gauge state in paused/uninterrupted comparisons.
- `test_runtime_present_c.py`: 256 native publication comparisons, 256
  fractional camera cases and write-range checks still pass.

Ordinary, runtime, VERIFY/runtime and input/runtime builds assemble. Pixel
writes are stubbed in gauge tests; full live gauge validation remains open.
The native flight-loop activation is still absent. The cockpit refresh/needle
audit below resolves +0AB20 as bitmap bookkeeping, not an elapsed-time timer.


### Cockpit repaint counts and direct needle geometry (C4g/C7e audit)

The decrement at +0AB20 belongs to bitmap repair. +0AA9C..+0AB12 pairs eight
restore descriptors with words at hunk 0 +0B04E..+0B05C; +0AB18 skips a zero
word, otherwise decrements it and passes the rectangle to +09274. These counts
must remain draw-owned under C7e. Advancing them on consumed fields could
exhaust the repairs before either physical bitmap is drawn.

Two indexed producers use the shared base +0B04C:

- +0AF36 maps an icon index through +0AFA4 and stores 2 at +0AF54 before
  updating its source artwork.
- +0B0A6 detects a changed numeric/text value, updates its cached value and
  stores 2 at +0B0CE using the descriptor's word at +12.
- The pitch-band artwork change at +0AC98 also stores 2 directly to +0B05A
  at +0ACE0. It is the same two-buffer repair request, not a flight timer.

The native needle routine +0AD30 has no incremental angular slew. Its input
byte selects a quadrant-reflected sine/cosine pair from +0AFC4; the routine
adds the fixed center and writes the selected buffer's endpoint bytes at
record +12/+18, then draws the line. The old endpoint does not influence the
new endpoint. +0AC14 restores the prior needle rectangles; +0ACF0 supplies
current instrument angles. Rendering the latest field-rate instrument value
therefore supplies the desired responsiveness without introducing a separate
needle integrator or consuming endpoint caches during skipped renders.

The ignored `test_cockpit_presentation_c.py` executes the native instructions:
24 restore-count cases (eight records, initial 0/1/2, six calls each) show
exactly 0/1/2 repairs; 41 producer cases cover all 32 icon mappings and nine
text dirty offsets; 512 needle cases cover all 256 angles in both buffers,
including repeated draws and randomized previous endpoints. The needle
oracle independently calculates lookup/quadrant geometry. All pass. Graphics
writers are stubbed, so this establishes state ownership and drawing arguments,
not live bitmap appearance. No game-code patch is required for these routines.

Current-view target drawing remains separate work: +046A4 calls +0A6E4,
which reads the selected descriptor and projected X/Y/model pointer from the
committed target block. Suppressing render-time selection alone does not
refresh that projection. A presentation adapter must keep the world-selected
identity while updating only the drawing inputs, and restore the committed
block before any world consumer runs. This audit does not claim that adapter
or the remaining complete-renderer isolation is finished.

### Current-view selected-target capture primitive (C5d, not installed)

`timing-target-view.i` captures the already world-selected identity from native
renderer projection scratch, without projecting the entire scene a second
time or invoking the selector. `target_view_prepare` validates the native
collector relocations and copies +0A450..+0A58A. Only operands accessing the
target block are redirected into the 490-byte private context; scene, model,
viewport and range reads retain their native bindings. Flush the copied code
before calling it. The context, native data and output must not overlap.

Before a frame, `target_view_reset` snapshots the committed 168-byte target
block, validates descriptor offsets, and clears private count/validity. At
each native collector site, `target_view_capture` first checks that the world
status is selected (byte 2) and that object identity/subtype matches the
snapshot. As in native selection, negative identities do not require subtype
equality. Only this identity reaches the copied collector, with an empty
private list. This prevents five unrelated candidates from filling the list
before the selected object is projected. Native viewport/range/model filters
still apply. A rejected later call does not erase an earlier accepted
projection of that same identity within the frame.

`target_view_build` returns a private presentation block with the selected
projection descriptor normalized into the first slot, native projected X/Y
and model pointer, and the original committed status/identity. It does not
sample pixels, choose a target, acquire a lock or touch RNG. When no projection
was captured after reset it returns 0 without writing output: the drawing
adapter must hide the current-view marker, not reuse a prior frame's result.
World identity/reuse certification remains part of C6b, not inferred here.

The ignored `test_target_view_c.py` compares 1,024 native-filter cases (65
captures and 959 ignored/clipped cases), including shuffled descriptor slots,
negative identities, viewport/range rejection and non-selected status. It
checks six unrelated candidates before the selected object, stale-frame
rejection, invalid-reset atomicity, register preservation and native-memory
write isolation. Preparation corruption checks cover each relocation plus
the first/last instruction. Graphics are not invoked in this primitive test.

Ordinary, runtime, VERIFY/runtime and input/runtime builds assemble. The
primitive is not yet bound to collector hooks, reset by frame publication,
or borrowed/restored around the native panel painter. Those integration and
live bitmap checks remain required; this is not completion of C5d or C.


### Target capture and panel borrowing in the runtime (C5d)

The experimental runtime now prepares the capture context in `RT_VIEW` and
starts a fresh capture epoch in `timing_runtime_present_state`, after private
camera/scene validation and before native presentation buffers are published.
`RT_VIEW_PHASE` is 0 closed, 1 collecting or 2 drawing; the arena is now
28,920 bytes. Activation clears a prior collecting epoch but rejects an
in-progress panel borrow. Presentation publication also rejects phase 2.

Under enhanced ownership, collector hooks +06356/+063D4 still call the native
collector during the admitted world visibility pass. During a presentation
epoch they instead call the private identity-filtered capture. Retained UI
world completion keeps its existing native visibility permission. No private
presentation capture runs during retained UI or after the panel closes the
epoch, so later projectile overlays cannot replace its target projection.

The CUSTOM1-only `timing_target_view_install` validates and patches +05C78
(panel call) and +046A4 (selected-object painter). `timing_runtime_target_panel`
saves the full committed target block, publishes a valid private projection
for native +0468C, then restores all 168 bytes and closes the epoch. The draw
hook skips +0A6E4 when the selected identity has no current projection. Other
native panel/sprite work still runs for an admitted epoch. An additional panel
call after closure cannot draw the stale projection. Ordinary native ownership
retains the native panel/draw paths. World consumption and rendering remain
serialized foreground operations; no world consumer runs during the borrow.
The existing selector hook excludes selection while the borrowed block is
visible. UI/drawing scratch outside the target block remains native-owned.

Verification in the ignored harness:

- `test_runtime_target_view_c.py`: actual collector/panel/draw hooks across 16
  visible/missing-target cases and four X positions, including a painter that
  deliberately overwrites the borrowed block. All committed bytes are restored;
  repeated closed-frame calls stay hidden. Native passthrough, CUSTOM1-off
  installation and six corrupt-call rejections pass. Graphics calls are stubbed.
- `test_target_view_projection_c.py`: 64 native scene views, six with selected
  candidates and three distinct screen projections; descriptors, X/Y and model
  pointers match native collection and the committed target block is unchanged.
  Rasterization is omitted. Each lane restores the same native projection
  scratch; fresh emulator instances prevent already-translated pre-patch call
  sites from bypassing hooks. Earlier attempts that reused either were rejected.
- The 448 existing ownership/ABI cases pass. Camera/instrument publication keeps
  its 256 native and 256 fractional-camera comparisons. Lifecycle tests retain
  240 PAL/NTSC fields across two arena addresses and now cover phase-2 rejection
  and activation reset. All build variants assemble.

This connects the projection adapter to the experimental rendering paths, but
native flight-loop activation remains absent. Real bitmap/TADS visual checks
across CPUs, prediction, complete renderer isolation, timing/latency and full
trajectory acceptance remain open. No claim of complete C5d or C is made from
these geometry/state fixtures alone.

### Compiled target-panel bitmap validation on 68000/020/060

The ignored `VP_PANEL=1` extension of `visibility_probe_c.i` now exercises the
actual target display hooks with real Amiga DMA. It runs after each native
visibility comparison, using the same original bitplanes for both lanes:

1. The reference lane draws native +0A6E4 from the first independently
   collected candidate's current descriptor, X/Y and model pointer. In views
   with no candidate it draws no selected object.
2. The enhanced lane starts with a synthetic committed selection of the same
   identity but deliberately stale X/Y (+16/+8). It resets private capture,
   runs the native scene prefix through the actual collector hooks, checks
   the captured descriptor/X/Y/model pointer against the independent reference,
   and invokes `timing_view_panel` with the real native painter. Empty views
   use an absent selected identity, exercising suppression of stale drawing.
3. The guest verifies all 168 committed target bytes are restored, the capture
   epoch is closed, and every byte of all five 8,000-byte bitplanes equals the
   reference output. The debugger only reads the result; all stimuli and
   comparisons execute in the compiled guest.

All sixteen PAL views pass on each of the 68000, 68020 and 68060 fixtures:
eight headings in each of two palette modes, ten nonempty and six absent
views per CPU. Candidate/pixel records agree across CPUs. Each session has
`panel_passes=16`, status 100 and completed 16. Reports and final reference
planes are retained under `tmp/dev/tmp/c/target-panel-{000,020,060}`. The normal
probe slave SHA-256 is
`e85b87bc2db1a2b360951a3bd8e6898a44205d11acc08f88e26392db986c785c`.

These are headless, host-mouse-disabled guest tests with VBL interrupts disabled
while DMA remains enabled. They validate real bitmap output and target-state
restoration in authored views, not live gameplay latency, every buffer/panel
transition, NTSC timing or full-flight authoritative equality. Native flight-loop
activation, object prediction and the remaining C acceptance gates are still
required. The diagnostic probe is not part of distributed slave builds.

The 68020 `VP_PANEL_SABOTAGE=1` negative control flips one byte in the saved
panel reference. It reaches the dedicated panel-bitmap failure (-9) before
any completed view, as required; the driver treats only that exact failure
as success for this control. Report: `target-panel-sabotage-020`. Corrupt-probe
SHA-256: `d82440dfa969443b086737857cb298570f69caa93aa511e6d58f39afcd6d5c3a`.
The probe builder places its code after VERIFY code and before its frame-log
storage, retaining 68000 PC-relative reach without altering the production
source. All four probe sessions reached terminal results and were closed.

### Prediction inventory: shared actor slots and identity barriers (C6)

The six projectile/effect slots are structure-of-arrays storage, not six
independent contiguous records. For slot `s=0..5`, native actor +0BED4 selects
`a1=h0+0C6D0+s` and `a2=h0+0C6A0+2*s`. Coordinate words at `a2+0/+12/+24`
are X/Y/height; `a2+36` is vertical motion state. Byte arrays relative to a1
include lifetime +0, type +6, animation +12, heading +18, negative/positive
turn limits +24/+30, target index +36, speed class +42, hit radius +48,
selected identity/subtype +54/+60, distance bucket +66, state +72, flags +78
and field-driven effect countdown +84. These names describe the observed consumers;
they do not certify every type's semantics.

Allocation word h0+0BA08 and eligibility word +0BA0C jointly admit an actor
at +0BF22. Guided constructors clear eligibility at +0BBC8..+0BBD2; field-owned
guidance later releases it. Prediction must not move an allocated but
ineligible actor. Type bit 0 branches past motion into lifetime handling,
so an allocated stationary effect is not a moving projectile.

The shared allocator +0BEA8 scans slots 5 down to 0, returning index+1 or 0
when full. Native callers found in hunk 0 are +09A1E (hit effect), +09B9A
(recurring/damage effect) and +0BADE (projectile constructor). A successful
allocation is a candidate generation-stamp boundary for all three; stamping
only the launch constructor would miss effects reusing the same storage.
The secondary word +0BA0A is not an identity counter: slot zero bypasses its
update. The allocator's final ADDQ.W sets CCR=0 on success and X/Z/C on full
failure. Any wrapper must reproduce those flags because callers branch on
its return immediately; merely restoring D0 followed by TST is insufficient.

Native release at +0C45E..+0C466 clears the allocation bit. A release followed
by allocation can return the same slot with the same final mask in one world
interval. Sampling masks at world endpoints therefore cannot certify identity.
Impact +0C3E8 sets type bit 0 and resets lifetime/countdown fields without clearing
the allocation bit. Terrain conversion +0C444 writes type 1, lifetime 64 and effect countdown 12.
These in-place representation changes also require prediction reset even
when the generation of the allocation has not changed. Expiry, guided release,
mission lifecycle changes and constructor initialization must have explicit
handling before prediction can be installed.

The ignored `test_actor_identity_c.py` executes the native fragments. All 128
allocator cases (64 masks, two initial secondary masks) match highest-free-slot
selection, mask writes and return flags. Native release followed by allocation
returns slot 5 twice with identical occupied-mask snapshots. All 768 impact
cases (six slots, 128 even type bytes) retain allocation while changing type,
lifetime and countdown. This establishes the need for constructor generations and
morph barriers; it is not implementation of either.

Movement cannot be inferred solely from the last coordinate difference:

- +0C078 resolves the target, +0C08E..+0C10A steers heading with byte arithmetic
  and turn bounds, and +0C10E..+0C210 derives speed-class/quadrant components.
- +0C220..+0C25E adjusts vertical motion from target height, except type-bit-3
  motion that retains its own vertical state.
- Distant motion uses the direct wrapped-word adds at +0C29E..+0C2DE. Near
  targets, +0C2E6..+0C40A divides motion into at-most-127-unit pieces, resolves
  targets again, and performs impact checks between those pieces.
- +0C41A..+0C450 checks terrain after movement; +0C456 decrements lifetime.
  Free-motion prediction must bound at known transitions and must never run
  these authoritative impact/release effects on the renderer's state.

The scripted index-5 object is a separate representation: +09FB0..+0A14A
reads/writes split object coordinates through +07B7E/+07BD0, steers via player
scratch heading +75, and finally adds native sine components of magnitude 50
at +0A104..+0A124. Its height follows player height minus 32 (or 24 below zero).
The preceding decisions include terrain probes and RNG; previewing this full
routine as though it were a pure velocity function would consume world effects.
Ground/static object tables and other scripted constructors still need a full
writer inventory. No family may inherit a previous occupant's endpoint based
only on a matching slot number or unchanged allocation mask.

### Shared-actor allocation generations (C6b, experimental runtime)

`timing-live-actor-generation.i` validates all 44 bytes of native +0BEA8..+0BED2
(instructions and relocated mask operands), copies that allocator unchanged,
and installs a CUSTOM1-only entry hook. All three constructor call sites
(+09A1E, +09B9A, +0BADE) reach it, including native calls retained by world
clones. Under normal enhanced ownership or the admitted retained-UI phase-4
world completion, a successful result 1..6 advances the corresponding private
32-bit generation. Full allocation failure does not advance any generation.
Native ownership and other UI phases execute the exact native allocator only.

`timing-actor-generation.i` stores six longwords and a sticky exhaustion mask
in 26 bytes at `RT_ACTOR_GENERATIONS`; the runtime arena is now 28,946 bytes.
Preparation and normal activation clear it. Generation zero identifies the
initial epoch's occupant, if any; the future predictor must clear its own
cached identities at the same lifecycle reset. A release/reallocation within
one world interval gets a new stamp even if the allocation mask ends unchanged.
The increment happens during allocation, before constructor initialization;
rendering/prediction must observe it only after serialized world work completes.

At FFFFFFFF the generation saturates and the slot's exhaustion bit is set.
Further allocations leave that bit set until lifecycle reset. A future
predictor must reject exhausted slots rather than compare the saturated value
as if it certified identity. No generation silently wraps to a prior value.
This hook does not yet certify eligibility transitions, impact morphs, the
scripted object or ground-object lifetimes; those remain separate barriers.

The tracking wrapper preserves native D0/D1 results and all other registers.
After recording, SUBQ.W/ADDQ.W reconstruct the allocator's original final
ADDQ flags, including X/Z/C when full. It does not read privileged SR or use
a post-68000 CCR instruction. The native fallback executes the copied routine
without this reconstruction.

The ignored `test_actor_generation_c.py` passes 1,536 exact native
register/CCR/mask comparisons across all 64 allocation masks, six ownership
states and four incoming user/supervisor CCR combinations. It rejects each of
44 corrupted signature bytes before copying/patching, checks CUSTOM1-off and
invalid READY behavior, exercises twelve overflow/repeated-allocation cases,
and verifies two allocations of the same released slot yield generation 2.
It also executes each of the three actual constructor JSR sites through the
patched entry on a fresh emulator, confirming each stamps its allocated slot.
Invalid standalone results 0/7/FFFF/FFFFFFFF do not write generation state.

The expanded lifecycle test verifies generation/exhaustion reset after valid
activation, retains atomic rejection, and still passes 240 PAL/NTSC fields at
two arena addresses. Ordinary, runtime, VERIFY/runtime and input/runtime builds
assemble. These are assembled 68000 instruction checks; live cross-CPU hook
validation and the prediction consumer are still open. No authoritative
motion or allocation policy was changed, and native flight activation remains
absent.

### Private shared-actor next-step preview (C6a/C6c, standalone)

`timing-actor-preview.i` copies native +0BED4..+0C69C, including its four
internal helpers and embedded distance table. All 120 absolute operands are
validated before preparation writes anything. Internal calls point into the
copy; mutable operands point into its private context. The apparent address
at +0C28A is an immediate followed by a branch opcode, not a relocation.
Native speed/turn/type tables remain read-only. Preparation requires the
usual instruction-cache flush before execution.

The 2,950-byte context contains the code and snapshots of allocation/eligibility
BA08..BA0F, selected identity AA0A..AA15, countermeasures h6+42E8..42E9,
B92C/9C52 scratch, and C6A0..C761 (six actors plus movement scratch). It also
copies 726 bytes of player/split-object state: the highest indexed access is
P+0256+127. The native helper updates player/decoy split coordinates only in
that copy. A6 holds the private context; the copied code does not change it.
The resulting poses preserve native steering, speed classes, word wrap,
vertical adjustment and near-target subdivisions. No private state is copied
back to the world, including allocation, lifetime, impact counters or damage
notifications. The impact sound call is replaced with three NOPs.

The terrain callback +0B3B2 is a bitmap/palette classification returning
only 0 or -1, not an arbitrary terrain-height query. Both values compare below
a strictly positive actor height at +0C42C. The preview substitutes zero
without graphics access and marks every queried nonpositive-height slot
uncertain. Such a slot cannot supply a predicted endpoint. This deliberately
does not pretend to know what a future displayed bitmap would classify.

`actor_preview_step` returns a candidate mask and retains the private next
poses. It excludes unallocated/ineligible slots, stationary effect types,
lifetimes zero/one, native release, type changes and uncertain terrain queries.
A decoy hit can increment C754 without changing allocation or type; because
that native counter is aggregate, any such hit conservatively rejects the
whole candidate set. This can freeze unrelated actors for an interval; it is
a safe provisional bound, not final visual acceptance or per-slot impact timing.

This primitive is **not installed or called by the runtime**. Its candidate
mask is not an identity certificate. The consumer still must capture/check
allocator generations, exhaustion, eligibility and lifecycle epoch, derive
the first interval from constructor/update order, cap the horizon to one
world tick, and publish only renderer-owned poses. It must run after serialized
world work, never between allocator entry and constructor completion. Other
object families and actual flight-loop activation remain open. Inclusion adds
code only to experimental timing builds; it enables no behavior with CUSTOM1
off (or on). The runtime arena remains 28,946 bytes.

The ignored `test_actor_preview_c.py` compares 1,200 complete native actor
steps (7,200 slot inputs) with private execution, including all snapshotted
mutable actor/player outputs. A second emulator runs the same 1,200 steps
with the other terrain return; every accepted position, vertical state and
heading agrees. The sweep accepts 421 slot endpoints, rejects 1,356 eligible
slots, encounters 18 uncertain terrain queries, 339 lifetime-one inputs and
502 type changes. A targeted decoy case proves rejection despite unchanged
type/allocation. Thirty terrain-stub cases cover all slots and signed-height
boundaries. All 122 corrupted operand/endpoint signatures reject atomically.
A write monitor and full native-state comparison observe no world writes.
These are assembled 68000 instruction tests, not live CPU/visual validation.

Ordinary, runtime, VERIFY/runtime and input/runtime builds assemble. A nearby
VERIFY branch bridge keeps LoadSeg dispatch within the 68000's signed-word
branch reach as experimental code grows; it tail-branches to the same verifier
and preserves its register/stack ABI.

### Shared-actor forward publication (C6a/C6b/C6c, experimental runtime)

`timing-actor-present.i` adds a 218-byte cache around the private actor preview.
Capture records the completed world tick/remainder, six allocator generations
and exhaustion bits, allocation/eligibility, four coordinate/vertical arrays,
actor bytes and candidate next coordinates. Publication first copies the
current committed coordinates, then replaces only certified slots. Tick,
generation, exhaustion, allocation/eligibility, coordinate/vertical or motion
byte mismatches leave that slot at its current committed position. Reusing a
slot with the same final mask and pose cannot borrow the previous generation's
endpoint. Lifecycle activation invalidates and reseeds the cache together with
allocation generations, before returning enhanced input ownership.

Two actor byte arrays are deliberately excluded from motion identity:
+12 is the effect animation frame, and +84 is its field countdown. The prior
inventory called +84 a model value; the field-effect owner and native +0BE5A
show it is decremented every field and restarted by animation/impact. Comparing
it would reject all flying-actor predictions after one field. Type, lifetime,
heading, turn limits, target, speed, hit radius, selected identity/subtype,
distance bucket, state and flags still must match. Type/lifetime changes catch
impact/expiry; the private preview additionally bounds decoy and terrain hits.
The cache assumes the established serialized native writers: eligibility is
cleared by construction and set by guided release. Arbitrary untracked writes
that change and restore bytes between observations are not certified.

Coordinates advance from current to the private next pose with the shortest
signed wrapped-word difference. Fractions use elapsed fields since capture
divided by fields to the next deadline: PAL 17/17/16 and NTSC 20. The deadline's
remainder is subtracted before computing elapsed fields, so a freshly completed
tick starts exactly at its committed pose. Negative fractional displacements
round down; additions retain native word wrap. There is no prior-tick buffer,
no accumulated render-step state and no prediction beyond the next tick.
Repeated or skipped renders do not change the result. Invalid clock inputs
reject without output writes; stale epochs and inconsistent phases snap to
committed coordinates.

`timing_runtime_actors` is bound through new optional consumer fields
TF_ACTOR_ENTRY/CONTEXT (TF_SIZE now 108). On normal world completion it runs
after all weapon/damage/script/tail effects and before scheduler acknowledgement.
It validates enhanced ownership (or retained-command completion), matching
field stamps, completed body phase and a new tick. Duplicate capture is rejected.
Script-modal completion remains suspended and gets a fresh snapshot on normal
activation. Flight-end paths do not admit another prediction interval.

The native weapons block calls the existing-actor update at +097B6 before its
later projectile constructors. Capturing after the whole world body therefore
starts a newly created eligible projectile's first visual interval at its
spawn pose and previews its first future native update. An ineligible guided
spawn is held. The initial cache held newly eligible guided slots until the next tick; the
separate release cache described below now covers that first interval. Live
visual acceptance remains open. No constructor
or weapon launch was moved to render time.

The runtime arena is 32,158 bytes: the prior state plus the enlarged consumer,
2,950-byte preview, 218-byte cache and 36-byte renderer coordinate buffer.
`timing_runtime_present_state` uses those private coordinates for scene input
publication. World visibility, target selection and geometry continue to build
from committed coordinates; native C6A0 actor coordinates are never replaced.
Preparation remains behind the default-off CUSTOM1 Enhanced framerate gate.
The main flight-loop consumer is still not installed.

Validation:

- `test_actor_present_c.py` checks real native-preview capture, 70 PAL/NTSC
  fractional frames and 70 repeated renders, signed/wrapped coordinate cases,
  133 individual identity/state barriers, same-pose generation reuse, exhausted
  slots, lifecycle/stale tick fallback, and atomic invalid phase/rate rejection.
  Its write monitor permits only the renderer output and stack during build.
- `test_runtime_actors_c.py` runs 600 consumed fields with batch sizes 1/3/10
  at both rates. It observes exactly one activation seed plus one capture per
  completed world tick. All 288 render publications match the independent
  fraction oracle; 218 show a pose ahead of committed coordinates. Final native
  player/actor state and cached endpoints match across batch sizes. Allocation
  reuse falls back and activation resets both cache and generations. Native
  audio/UI and clear-terrain callbacks are fixture stubs; this is not pixel
  validation. A first far-distance fixture exercised native signed-word
  collision wrap and was correctly rejected; the free-flight fixture uses
  ordinary native distances.
- Existing activation (240 fields at two arena addresses), camera publication
  (256 native plus 256 fractional cases), retained-boundary (12 cases) and batch
  (1,200 fields) tests pass. Retained-boundary comparison now includes the
  complete actor cache. Ordinary, runtime, VERIFY/runtime and input/runtime
  builds pass.

The verifier's references to earlier seed/patch-table data now use a local
PC-relative base plus a long displacement, avoiding the growing runtime's
68000 signed-word reach limit without absolute load-address assumptions.

C6 is not complete: guided first-release handling, other object families,
per-slot impact refinement, live hook/bitmap checks, visible projectile error
and CPU cost remain open. This publication is reached by the experimental
runtime harness, not yet by an activated native flight loop.


### Guided first-release prediction (C6b, experimental runtime)

The native guided constructor clears its slot's eligibility at +0BBC8..+0BBD0.
Field guidance state 5 sets that bit at +0A234..+0A242. The existing native
single guided-slot word BA0E identifies the affected actor; new constructors
run only on world ticks. This makes release a field-stamped transition within
an already captured allocation generation, not a new launch from rendering.

The flight consumer now also invokes its actor-presentation callback after
non-deadline field completion. It requires matching delivered field stamps,
no pending world deadline, the current world snapshot, an occupied native
guided slot that was previously ineligible, matching allocation generations
and neither current nor captured exhaustion. When admitted, it runs the private
native preview once and captures a separate release cache at that clock phase.
Only that slot's safe bit is retained. A rejected preview is not retried later
in the interval. A release on a world-deadline field is naturally handled by
the world update and normal post-world capture instead.

The release cache starts at the committed release pose (fraction zero), then
uses elapsed fields since release divided by remaining fields to the next
world deadline. `actor_present_capture` therefore now admits phases 0..59;
its caller additionally requires phase below the configured field rate. The
same signed/wrapped fraction builder handles both world and release anchors.
This does not advance authoritative projectile motion, hit tests or damage.

Presentation first builds all normal world-anchored actor positions, then
merges only the certified released slot from a separate 36-byte buffer. It
never rebases unrelated trajectories at release. Normal world capture and
lifecycle activation invalidate the release cache. Existing generation,
exhaustion, motion-state and stale-tick checks still apply when publishing it.
The arena grows by one 218-byte cache and one 36-byte buffer to 32,412 bytes.
All entry paths remain within the existing CUSTOM1-gated runtime.

`test_runtime_actor_release_c.py` exercises native construction and the complete
field guidance sequence for weapon selections 1 and 3. With fire recorded at
field 3, first launch occurs at field 17 PAL / 20 NTSC and native release follows
seven fields later, at 24 / 27. Across batch sizes 1/3/10 it checks 960 fields,
exactly one release capture per interval, the renderer fraction independently,
unchanged committed actor coordinates, unchanged normal prediction cache and
a second in-flight actor whose prediction must not restart. At single-field
render cadence PAL has ten first-interval views (nine moved after release),
NTSC thirteen (twelve moved). Native final state and capture events match across
batch sizes. Four additional real-release runs (96 fields) suppress the cache
when generation, current exhaustion, captured exhaustion or captured allocation
identity is lost. The fixture stubs the native world's audio/UI and clear-terrain
callbacks; these are instruction tests, not rendered-pixel or cost measurements.

The fraction test now covers every valid phase at both rates: 1,072 initial
and 1,072 repeated renders, plus 133 identity/state barriers. Activation still
passes 240 fields at two arena addresses; all twelve retained-boundary cases
pass. Allocation-hook regression passes all 1,536 native ABI comparisons and
44 signature rejections. Ordinary, runtime, VERIFY/runtime and input/runtime
builds assemble. The near verifier entry now uses a position-independent long
address calculation, and allocation-hook CUSTOM1 access does likewise, to
avoid the larger build exceeding 68000 signed-word reach.

Live cross-CPU release/pixel checks and visible first-interval trajectory
acceptance remain open, alongside the other C6 object families and main-loop
activation. No full-C or release-readiness claim follows from these tests.
