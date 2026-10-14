# Warrior basic combo v2

World chooses the combo and each step. The client sends only `request_attack(sequence)`.
Animation, multiplier, hit reaction and step index cannot be supplied by that command.
No Ability framework, skill books or skill persistence is introduced.

## Definitions and runtime

| Server selection | Definition | Native clip suffixes |
| --- | --- | --- |
| Combo OFF, skill 0/1/2 | warrior_basic_4 | 01 → 02 → 03 → 04 |
| Combo ON, skill 1 | warrior_combo_5 | 01 → 02 → 03 → 05 → 07 |
| Combo ON, skill 2 | warrior_combo_6 | 01 → 02 → 03 → 05 → 06 → 04 |

Enabling Combo at skill zero is rejected. `BasicAttackComboState` tracks the
zero-based current step, last accepted swing time, enabled flag, runtime skill
level and weapon mode. The shared `BasicAttackComboDefinition` holds an array of
`BasicAttackStepDefinition`, which extends the existing `AttackHitDefinition`.

**The finisher is the last step of the active definition, not a fixed stage or
animation number.** Each authored final step requests KNOCKDOWN with the existing
1.5 damage multiplier; other steps request FLINCH with multiplier 1.0. Requested
reactions still pass through `HitReactionResolver` and target profiles. Knockdown
remains 1.2 s down + 0.4 s get-up. Final steps separately author 2.5 m physical
knockback; no per-hit stun or hardcoded third-hit displacement returns.

Changing enabled state, skill level/selected definition or supported weapon mode
resets the next chain to step zero. Completing the definition or exceeding its
1100 ms reset interval starts a new chain. Interruption/death resets continuity;
disconnect removes the player's runtime. Skill level persists only for that session.

Pending swings store combo key, zero-based index, exact animation key, impact
deadline, attack stat and a private copy of the resolved step (all hit fields).
Changing Combo after acceptance preserves that pending hit. Knockdown/death cancels
it; impact never looks up a new step from the player's current chain.

The small server API is `set_combo_skill_level(peer_id, 0..2)`,
`set_combo_enabled(peer_id, enabled)` and `set_combo_weapon_mode(peer_id, mode)`.
Only onehand_sword currently has playable definitions. Unsupported modes are
rejected. Two-handed native clips remain independently named in the presentation
library, ready for separately authored definitions rather than reusing sword timings.

C sends `request_combo_toggle()` for the caller's character; this cannot change
skill level. The existing debug HUD displays server enabled/level/chain length.
For local editor-engine World startup, append `-- --dev-combo-skill=1` or `=2` to
the World command. Default remains skill zero and Combo OFF. These are development
controls, not a skill progression implementation or a new UI window.

## Inspected asset and timing provenance

The existing local, ignored asset is
`dev_assets/legacy/players/warrior/warrior_all_motions.glb`. Live Godot 4.7.2 inspection
found one AnimationPlayer, root `..`, and the default unnamed AnimationLibrary.
It contains separate `onehand_sword__combo_01..07` and
`twohand_sword__combo_01..07`. No asset was re-exported or regenerated.

| One-handed clip | Imported duration (s) | Impact (ms) | Recovery / next accepted swing (ms) |
| --- | ---: | ---: | ---: |
| onehand_sword__combo_01 | 1.000000 | 260 | 533 |
| onehand_sword__combo_02 | 0.933333 | 270 | 543 |
| onehand_sword__combo_03 | 1.066667 | 290 | 418 |
| onehand_sword__combo_04 | 1.266667 | 620 | 1267 |
| onehand_sword__combo_05 | 1.166667 | 410 | 661 |
| onehand_sword__combo_06 | 1.333333 | 420 | 694 |
| onehand_sword__combo_07 | 1.266667 | 620 | 1267 |

Two-handed durations for 01..07 are respectively 1.666667, 1.500000, 1.333333,
1.600000, 1.600000, 1.500000, 1.600000 s. They are inspected, not playable content yet.

The staged `combo-reference.json` contains MSA provenance. Original files were
also inspected under the external local reference
`N:/Mandate Local/metin2/bin/pack/PC/ymir work/pc/warrior/onehand_sword/`.
The initial intermediate impact was the rounded midpoint of AttackingStartTime/AttackingEndTime,
a first-pass single-hit approximation of native continuous weapon collisions.
Recovery uses rounded DirectInputTime. In particular 03 can link before the end
of its full attack window; this implementation resolves one hit, not the original
continuous window or input buffer.

Initial finisher impacts used MotionEventType 4 StartingTime: 0.659316 / 0.653366 s.
Their normal attack-window fields are zero/missing, not evidence of no attack.
Finisher recovery uses the complete native duration. All timings are explicit
Resource data, independent of animation callbacks.

The Combat Feel pass retuned impact against final Godot-imported, retargeted
clips at native speed. A disposable diagnostic sampled the equipped blade segment
against a fixed frontal contact point (1.5 m ahead, height 0.7 m), in 10 ms samples
with 5 ms AnimationPlayer advances. It evaluated 4/5/6 chains, including 04 after
03 and after 06, with blend 0 and 0.08 s. Both blends produced the same nearest
contact sample. Updated impacts are 260/270/290/620/410/420/620 ms for 01..07;
recovery is unchanged. This geometric proxy is a tuning baseline, not a human
assessment of hit feel or a server hitbox test. Final live review can adjust each
step independently. No animation callback or marker authorizes damage.

Finisher displacement is resolved independently from reaction. Accepted KNOCKDOWN
can carry profile-scaled distance; resisted/repeated knockdowns carry zero. Server
physics applies a horizontal impulse with exponential damping and scenery collision,
while AI/input remain locked. Existing position snapshots replicate the motion.

## Combat geometry

[Warrior Combat Trace v1](warrior-combat-trace-v1.md) now supplies baked actor-local
blade geometry for all seven one-handed combo clips. Damage/reaction/timing remain
in the step. A definition without a trace retains the sphere/cone fallback.

## Playback boundary

`receive_swing(peer_id, animation_key, step_index, recovery_ms, finisher)` is an
authority-only event. Clients play its exact animation identity. The finisher flag
only colors the temporary slash ribbon; damage/reaction come from the frozen step.
One-based `combos` in snapshots remains a display field only. `combo_options`
reports enabled state, runtime skill level and selected definition length.

Playback keeps native speed 1.0 and default 0.08 s crossfade.
`attack_blend_seconds` is a small presentation setting for focused comparison. An accepted
successor replaces the preceding native clip at its server recovery/link time;
an isolated swing can finish naturally before idle. No silent attack_3 fallback
remains. Missing required clips report their exact key and asset path. The optional
`--require-dev` presentation check requires the complete seven-clip set.

Local development resolves the all-motion model. For the existing armor mesh,
the presentation adapter copies the necessary clips from that same asset and
retargets node prefixes to the armor skeleton's matching native bone names.
Locomotion aliases remain idle/run/hit/death. Planar root movement is neutralized
on private animation copies. World never loads these optional visuals; exported
clients without final assets retain the tracked procedural placeholder. The source
GLB, MSA files and reference metadata remain local/ignored, outside public builds.

## Verification and remaining manual review

- Default smoke: exact 4/5/6 definitions, OFF at all three levels, ON selection,
  toggle/timeout/interruption resets, immutable pending copy, and existing reaction
  profiles/action-lock contracts; existing item/economy/Web bridge checks remain.
- Two real WebSocket clients: four and six hits, observer's exact ordered animation
  keys, server-resolved extended steps, knockdown only after final impact, toggle
  during a pending swing, player pending cancellation, immunity/death/respawn.
- Warrior placeholder and complete local base/armor rigs: required clip validation,
  in-place root, hand socket, flinch preserving an attack, lock and idle transitions.
- Metin network encounter: damage/contribution/waves/reward/pickup remain functional.
- Native Forward Mobile rendering on RTX 4070: ran all three chains and inspected
  rendered impact/idle frames for both Warrior variants. Different 05/06 poses,
  native 04/07 finishers and return to idle are visible.

**Full live manual feel review remains incomplete.** Windows Computer Use could
select the native window, but screenshot capture failed twice with
`FrameArrived timed out` / `window capture timed out`. Native renderer captures
provide pose evidence, not proof of continuous crossfade smoothness, blade contact
quality or a live server's perceived hit latency. Existing extension teardown
warnings about ObjectDB/resources remain; no script errors are accepted.

Launch one focused native review window from the repository root:

```powershell
& ./.godot/Godot_v4.7.2-stable_win64.exe --path . --mode=client res://tests/warrior_compatibility.tscn -- --require-dev --preview --combo-review
```

Keys 1/2/3 loop 4/5/6 respectively; B toggles attack blend 0/0.08 s; Esc closes. This is a presentation fixture
using the production visual, definitions and reaction resolver, not an alternative
authoritative gameplay path. Review chain transitions, root/facing, impact feel,
finisher/down/get-up and idle return. The fixture shows reaction presentation;
physical displacement is verified separately by server/network checks. `--combo-capture` instead renders each chain
once, saves fixed-name diagnostic PNGs under `.godot/verification`, then exits.
It is optional, not part of smoke or a pixel snapshot test. In-world gameplay still
needs a final human feel pass after restarting both World and client for the new RPC.
