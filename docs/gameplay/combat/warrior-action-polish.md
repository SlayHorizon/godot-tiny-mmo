# Warrior basic action polish

Small follow-up to Combat Feel v2. Attack Speed, preinput/direct/limit timing,
impact timing, damage rules, baked traces and hit windows are unchanged.

## Scheduled impact survives a hitch

World still schedules exactly one resolution per accepted step. The resolver
requires `now >= swing.impact`, then validates the accepted step's canonical
impact against its canonical active window. A late physics tick no longer tests
its current elapsed time against that window and discards a legitimate hit.
The resolved flag/hit set still prevent duplicate damage. This does not rewind
targets: damage uses the current authoritative body positions and collision
state when World resolves the scheduled impact. Interruption/death checks remain.

## Link, motion lock and advance

`PlayerCombatRuntime.next_attack_ms` remains the combo transition deadline. The separate
`movement_unlock_ms` covers the full motion duration, scaled by the accepted
Attack Speed ratio. A successor accepted at DirectInputTime replaces that action
and its lock. Without a successor, normal input movement remains blocked through
the clip's tail. The new `motion_duration_ms` rounds up the canonical
MotionDuration to milliseconds, not a replacement for existing recovery/direct values.

BasicAttackService starts a small forward action on each accepted swing. PlayerActor3D
integrates a smoothstep travel curve through its existing `move_and_slide()`.
The direction is the frozen attack yaw. The original version compressed travel
into link/recovery time. [The follow-up BODY pass](warrior-body-collision.md)
stretches travel over the full scaled motion instead; early chaining discards the
unused remainder. Distance is never multiplied by Attack Speed. A successor starts
its own advance in its newly accepted direction. Interruption clears remaining
advance; knockback retains its separate simulation. The follow-up also adds
asymmetric player-to-mob movement blocking without changing defending geometry.

## Authoring evidence

The local original MSA files contain explicit accumulation for 01–04. The current
all-motions GLB retains native bone tracks, while VisualAnimationTools removes
planar root translation from presentation instances. Its raw Bip01 endpoint
delta is a residual skeletal delta, not an equivalent actor accumulation (for
example 02 is only several centimetres, whereas MSA accumulation is 85.25 cm).
Runtime World never reads the GLB, Skeleton or AnimationPlayer.

| Clip | MotionDuration, ms | Advance, m | Source |
| --- | ---: | ---: | --- |
| 01 | 1000 | 1.3176 | MSA Accumulation Y = -131.76 cm |
| 02 | 934 | 0.8525 | MSA Accumulation Y = -85.25 cm |
| 03 | 1067 | 1.4301 | MSA Accumulation Y = -143.01 cm |
| 04 | 1267 | 1.0552 | MSA Accumulation Y = -105.52 cm |
| 05 | 1167 | 0.7 | Explicit temporary gameplay authoring |
| 06 | 1334 | 0.7 | Explicit temporary gameplay authoring |
| 07 | 1267 | 0.7 | Explicit temporary gameplay authoring |

Only the forward component is used; 04's lateral accumulation is intentionally
not applied. The MSA files for 05–07 lack Accumulation. Their 0.7 m values are
clearly authored fallback values, not inferred or claimed original motion data.
All distances live on the step resources and remain independently tunable.

## Presentation

At an accepted swing the client actor adopts the authoritative yaw immediately.
Its WarriorVisual3D preserves the previous visible heading as a local offset and
blends that offset to zero over 70 ms. The new trace therefore uses the new yaw
from acceptance, while the rendered model can turn smoothly. No server yaw
interpolation or movement-authority change is introduced.

Confirmed hit messages include the accepted `finisher` flag. MandateCamera3D
accepts positive-damage local finisher confirmations once per action ID, regardless
of target count. Remote attackers and misses produce no impulse. The impulse uses
small Camera3D horizontal/vertical frustum offsets for 110 ms with fast decay;
it writes no player transform, persistent orbit yaw/pitch or zoom.

SwordTrail3D retains one ImmediateMesh and clears/rebuilds its surfaces rather
than allocating a new mesh resource each frame. Its sampling, material and fade
are unchanged. Player labels retain `Lv X · Name` with font 22 / pixel size .006,
slightly more prominent than the mob font 20 / .006. Hit spark contact placement
remains the existing client capsule fallback.

## Verification and preview

The opt-in two-client action suite checks scheduled-hit lateness/uniqueness,
early-hit rejection, separate link/movement deadlines, full single-motion input
lock, successor yaw/advance ownership, equal distance at AS 100/122/150, shorter
execution time, real scenery collision, visual turn blending, once-per-action
local shake, miss/remote suppression and trail mesh identity:

```powershell
& ./tests/run-combat.ps1 -Scene warrior_action_polish -MarkerPrefix ACTION
```

The original link-compressed measurement completed in 32 / 27 / 22 physics ticks
at AS 100/122/150. The follow-up full-motion measurement completes in 60 / 50 / 41
ticks while retaining approximately 1.3176 m for an uninterrupted first step.
The real wall test uses the same physics world as the authoritative character.
Existing combat and trace fixtures separate fixed-position geometry assertions
from advance; combat also verifies camera impulses against unique received local
finisher actions. Advance is exercised independently by the real-physics suite.

Preview uses existing Warrior compatibility tooling:

```powershell
& ./.godot/Godot_v4.7.2-stable_win64_console.exe --path . --mode=client res://tests/warrior_compatibility.tscn -- --require-dev --preview --combo-review --feel-review --feel-pack=50
```

S toggles single/chain. G toggles a direction change between steps. Existing
1/2/3, Q/E/R and B controls retain combo length, speed and animation blend.
Preview movement is an illustrative tween; collision/authority are tested in
the World fixture, not delegated to that tween. `--action-capture` runs single,
straight chain and turning chain once and saves disposable verification frames.
Its native Windows/Vulkan Mobile run completed with `WARRIOR_ACTION_RENDER_OK`:
the straight finisher confirmed 13 targets and the turning finisher missed,
exercising both presentation cases. Captured frames show advance, changed facing,
trails, damage numbers and compact mob labels. No subjective live-input or audio
claim is inferred from captures. Known engine/extension teardown diagnostics
remain; there were no GDScript/parse failures in the passing run.

The remaining human gameplay checklist is: single Space plus WASD during the
motion, held Space through a pack, direction change near a link, and a confirmed
finisher versus a miss. This verifies input/feel in the normal CEF client rather
than treating the controlled preview as a full manual World playtest.

Passing automated checks: whitespace/import, default smoke (10 Godot cases and
74 Web UI contracts), the new two-client action suite, existing FEEL2 and combat
network suites, CombatTrace geometry plus 50/100-target network checks, and the
two-client Metin flow. Network checks ran sequentially on their fixture port.
