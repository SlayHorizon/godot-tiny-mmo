# Warrior Combat Feel & Presentation v2

This pass shares Attack Speed between the authoritative basic-combo timeline and
client animation playback. Imported clips, baked CombatTrace geometry, damage
rules and persistence policy remain unchanged.

## Attack Speed and canonical timing

`PlayerResource.BASE_STATS[Stat.ATTACK_SPEED]` is 100. Equipped ItemDefinition
stats contribute additive bonuses through the existing inventory aggregation.
The Iron Sword and development practice sword each define `attack_speed = 22`.
Unequipped baseline is 100; either equipped sword produces 122. The practice
sword retains its development-only total damage override of 1.

World loads equipment/stats into `runtime_equipment` on entry and refreshes that
cache after successful item transactions. Combat reads that authoritative RAM
cache, not SQLite. `runtime_attack_speed_ratio()` returns `attack_speed / 100`;
missing, nonfinite or nonpositive stats reject attack acceptance. Each accepted
step freezes its attack, ratio, definition, action ID and yaw.

The combo resources retain their existing impact, hit-window and recovery
numbers. Newly recorded PreInputTime, DirectInputTime and InputLimitTime come
from the original onehand-sword MSA files, in canonical milliseconds at AS 100:

| Clip | PreInput | DirectInput | InputLimit |
| --- | ---: | ---: | ---: |
| 01 | 167 | 533 | 603 |
| 02 | 101 | 543 | 637 |
| 03 | 85 | 418 | 665 |
| 04 | 1058 | 1058 | 731 |
| 05 | 295 | 661 | 849 |
| 06 | 214 | 694 | 944 |
| 07 | 1267 | 1267 | 1267 |

Runtime deadlines use `ceil(canonical_ms / ratio)`. The subsequent
[action polish](warrior-action-polish.md) evaluates the accepted scheduled impact
against the canonical window, so a late server tick cannot discard it. Neither
samples nor spatial bounds are scaled. AnimationPlayer receives that accepted ratio directly; it does not
derive a separate speed from client inventory state. Nonattack clips keep their
normal playback speed.

| Four-hit base combo | AS 100 | AS 122 |
| --- | ---: | ---: |
| Step starts, ms | 0 / 533 / 1076 / 1494 | 0 / 437 / 883 / 1226 |
| Through final recovery, ms | 2761 | 2265 |

These are scheduled minimum timelines with input already buffered. Actual World
transitions happen on the first eligible 60 Hz physics tick, and reliable delivery
adds client latency. This removes the old polling gap, not transport/tick latency.
The full imported clip durations still equal their original MotionDuration;
nonfinal clips can be replaced at DirectInputTime before their tails finish.

## One-intent buffer and facing

Per peer, World holds one accepted current attack and at most one queued sequence.
Before PreInputTime an intent cannot queue. A valid intent inside the input window
is consumed once at DirectInputTime. Later input starts a fresh chain rather than
extending an expired one. Monotonic sequence validation also rejects replays while
a request is buffered. A correctly queued slow attack bypasses the old inactivity
reset, which was unsuitable once attack speed could lengthen a step.

Finishers queue a fresh chain at their recovery/end, not an early continuation.
This also gives the native final 04 timing (DirectInput later than InputLimit) an
explicit terminal policy without altering its source values.

The local hold/autoattack path sends one intent at the accepted preinput boundary;
it no longer polls every 100 ms throughout recovery. A rejection can return a
retry deadline for early input or an action lock. Replayed sequences receive no
retry response. Releasing input does not cancel an already accepted queued swing.
Knockdown, interruption, death and disconnect clear current/queued intent state.

Validated movement input records desired next facing before action-lock movement
suppression. It cannot rotate the current trace. At the next accepted step World
consumes the latest direction recorded during that swing (or recent free movement),
then freezes the new yaw. Accepted swing messages also carry yaw so old position
snapshots cannot temporarily rotate the client presentation during the step.

## Presentation

- Basic-attack blend defaults to 50 ms. The optional preview compares 80/50 ms;
  blending does not change authoritative impact/recovery values.
- SwordTrail3D samples the animated weapon base and a local blade-tip marker.
  It keeps up to ten samples for 100 ms, creates a transparent world-space ribbon
  only in the active swing window, and fades the remaining samples afterwards.
  The marker describes the current 1.3 m sword visual, not a generic weapon API.
- Confirmed hit messages contain attacker, target kind/identity, action sequence,
  combo step, damage and resolved reaction. Metin identity uses its spawn-specific
  stone ID. No VFX coordinates are sent and HP snapshots create no hit feedback.
- CombatFeedback3D deduplicates by attacker/action/target and pools up to 64
  outgoing labels and 96 sparks. Only the local attacker's damage numbers appear;
  remote confirmed hits can produce sparks/sound. Labels rise and fade over
  850 ms; small shared-mesh sparks last 180 ms. There is no predicted-hit path.
- A replaceable AudioStream hook plays on confirmed hits. The current sound is a
  short generated placeholder with slight pitch variation. One spatial player
  rate-limits pack impacts to avoid dozens of simultaneous voices.
- Normal mob labels use smaller text and a small HP bar. Exact HP appears only
  for the selected mob. World creates none of these presentation nodes.

## Verification

Default smoke remains small: equipped/unequipped Attack Speed is covered by the
existing item test. The focused speed/buffer/feedback suite is opt-in:

```powershell
& ./tests/run-combat.ps1 -Scene combat_feel_v2 -MarkerPrefix FEEL2
```

It covers AS 100/122 deadlines and visual ratio, frozen speed/yaw, one queued
intent, direct-time transition, replay rejection, expired input windows, slow
buffered chaining, toggle immutability, knockdown/death cleanup, miss/duplicate
feedback, remote number suppression and pool reuse for 20/50 confirmed targets.
The existing two-client combat fixture observes accepted swings rather than the
retired decorative mesh. Metin fixture scenario boundaries wait for accepted
current/queued attacks to settle before changing player facing/position.

Optional native preview with real local Warrior and Wild Dog visuals:

```powershell
& ./.godot/Godot_v4.7.2-stable_win64_console.exe --path . --mode=client res://tests/warrior_compatibility.tscn -- --require-dev --preview --combo-review --feel-review --feel-pack=20
```

Keys: 1/2/3 select four/five/six hits; Q/E/R select AS 100/122/150; B compares
80/50 ms blend; V changes armor; Escape closes. `--feel-pack=50` checks a dense
pack. `--feel-capture` runs both blends and all speed/length combinations once,
saving disposable frames under `.godot/verification`. Preview confirmations are
synthetic fixtures using the production presentation classes, not server rewards.

On the tested Windows/Vulkan Mobile build, the 50-dog native capture completed
with `WARRIOR_FEEL_RENDER_OK`; inspected frames show animated weapons/ribbons,
numbers and HP bars. CPU feedback checks were roughly 1–2 ms for 20/50 headless
confirmations including duplicate/pool assertions. Native preview usually measured
2–4 ms for trace checks and feedback creation for 19–26 hits among 50 dogs, with
the first allocation around 5.5 ms. These are rough CPU timings, not GPU frame
time or an input-latency benchmark. Dense overlapping nameplates remain crowded;
no occlusion/decluttering system was added.

Captured frames establish rendering, not subjective continuity, audio quality or
live keyboard/CEF interaction. A human gameplay pass in the normal World remains
necessary for those judgments. The native fixture does not replace that playtest.
Known extension teardown diagnostics (four ObjectDB/three resources) still appear
at process exit; no GDScript/parse failures occurred in the passing checks.

Completed checks on 2026-10-11: whitespace/import, default smoke (10 Godot cases,
74 Web UI contracts), the focused FEEL2 suite, existing two-client combat,
CombatTrace geometry plus its two-client 50/100-target suite, Metin encounter
contracts and two-client Metin network flow. Network suites ran sequentially.
