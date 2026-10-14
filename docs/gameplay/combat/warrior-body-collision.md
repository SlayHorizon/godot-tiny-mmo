# Warrior motion advance and asymmetric BODY collision

Small follow-up to baseline `9d30697`. Attack Speed, input buffering, link times,
movement lock, hit windows, CombatTrace, damage, reaction profiles, knockback,
replication and visual facing remain unchanged.

## Full-motion displacement

World starts each advance with the accepted scaled `timing.motion`, rather than
DirectInputTime or recovery. The existing smoothstep integrator remains an
approximation; it is not reconstructed GR2 root motion. A successor at the
existing DirectInputTime replaces the advance and drops its unused remainder.
There is no residual advance added to later steps and no finisher exception.

MSA forward distances remain 1.3176 / 0.8525 / 1.4301 / 1.0552 m for 01–04.
05–07 remain explicit temporary 0.7 m gameplay fallbacks, not recovered Metin data.

Real-physics results for unchained 01: approximately 1.3176 m at AS100/122/150,
finishing in 60 / 50 / 41 physics ticks. At AS100, chaining at the existing 533 ms
link consumes approximately **0.724587 m**, or 55% of the full distance. The next
step owns its own duration, distance and direction. AS changes duration only.

## Two distinct volumes

The existing defending capsule stays radius 0.4 m / height 0.8 m / bottom 0 for
dogs. Its CollisionShape3D is disabled for physics but retained as CombatTrace
metadata. Narrow-phase hit detection still uses these canonical defending values.
The actor's enabled physics shape is a separate movement capsule configured by
`MobDefinition.movement_body_radius` and `movement_body_height`.

Wild Dog uses radius **0.6 m**, height **1.2 m**, bottom 0. The initial defaults
also apply to other current dog variants and can be authored per definition.
Definition validity requires finite positive radius and height >= diameter.
This does not enlarge `combat_radius()` or change trace data. Broad-phase queries
still find the mob actor on its existing layer and narrow-phase checks defending
geometry, so the larger BODY does not itself make a valid combat hit.

| Actor | Collision layer bits | Movement mask bits |
| --- | --- | --- |
| Player | 2 | 1 (scenery) + 4 (mob BODY) |
| Live mob | 4 | 16 (floor) |
| Mob during existing knockback | 4 | 16 + 1 (scenery) |

Walking retains native sliding against BODY and scenery. Before an attack's
planar motion reaches `move_and_slide`, a native `test_move` limits it to the
straight travel available before actor BODY contact. The tangential remainder
is discarded; scenery sliding remains native. The curve still advances on every
tick, so blocked travel cannot be banked or caught up when a mob leaves.

A second native query finds mob BODYs already penetrating the player's capsule.
For this simulation call only, these bodies are collision exceptions: recovery
cannot push an idle player sideways or add an unsolicited jump to walking.
A planar direction toward any overlapping mob is blocked; an outward direction
can leave the existing overlap. Exceptions are removed immediately after the
move, so new BODY contacts still block. There is no position correction, mob
shape/layer change, symmetric mob collision or separate combat resolver.
This is a small policy for existing overlap, not a general crowd escape solver.

Mob chase does not add the player layer; its scenery policy is unchanged. Death
and client snapshot activation retain the existing actor layer toggling.

## Finisher behavior

The real World fixture first blocks the finisher against the mob BODY, then
resolves the existing trace hit and reaction/knockback. The same advance continues
as the dog is physically displaced. In the fixture, Warrior Z moved from 9.950
before impact to 9.422 afterwards; the dog moved from 9.0 to approximately 6.512.
No blocked displacement is banked or replayed. Only the remaining authored motion
can use newly freed space, so a fully exhausted advance cannot catch up later.

## Oblique contact and pack overlap follow-up

The two new cases stay in `warrior_action_polish`; they are opt-in real-physics
checks, not new smoke or pixel/animation fixtures.

| Case | Before the correction | After the correction |
| --- | --- | --- |
| Attack, 30 degree BODY normal | 0.438 m sideways | 0.008–0.010 m sideways |
| Attack, 45 degree BODY normal | 0.279 m sideways | 0.0027 m sideways |
| Idle overlap with 5 / 10 / 20 dogs | 0.734 / 0.800 / 0.874 m recovery shift | 0 m planar shift |
| First outward tick with 5 / 10 / 20 dogs | 0.741 / 0.831 / 0.934 m | 0.0833 m, matching requested walking |

The angle case also verifies the contact position and that exhausted blocked
advance cannot catch up after the dog leaves. The pack case deliberately starts
with deep overlap and several penetration directions, with a common outward
route toward +Z. It checks idle stability, blocked inward movement, 1.5 m outward
walking, per-tick displacement, restoration of transient exceptions and BODY
blocking on re-entry.
Turning back into the same pack then resolves the production finisher trace and
reaction path: all 5 / 10 / 20 dogs are hit and physically displaced by knockback.
This does not prove escape from a fully enclosed ring or subjective combat feel.
A normal CEF playtest with 15–20 actively chasing mobs, attempted escape and a
full combo remains the manual stress check.

## Dead player freeze

Lethal damage marks the authoritative character dead immediately and clears
velocity, knockback and remaining advance. A dead character skips simulation
including `move_and_slide`: zero input alone would still allow collision recovery
against moving mob BODYs to displace the corpse. Respawn marks it alive again.
The ACTION fixture checks a mob moving through an overlapping corpse, unchanged
corpse position despite input, and resumed movement after the real respawn path.

## Verification and native preview

The opt-in action network suite covers full-distance speed scaling, successor
replacement, walking/advance BODY blocking, hit resolution despite blocked
advance, unblocked mob chase, existing-overlap escape and finisher knockback
opening space. The existing hitch, input lock, visual facing and shake contracts
remain in the same suite:

```powershell
& ./tests/run-combat.ps1 -Scene warrior_action_polish -MarkerPrefix ACTION
```

The existing illustrative combo preview now also uses full motion and cancels
its previous step's tween when starting a successor. It is not a physics test.
For BODY inspection, use the dedicated actual-physics native preview:

```powershell
& ./.godot/Godot_v4.7.2-stable_win64_console.exe --path . --mode=client res://tests/warrior_body_preview.tscn -- --require-dev
```

It shows cyan defending volume and amber movement BODY, plays the current
four-hit data, and applies the existing reaction resolver/knockback for preview
hits. `S` toggles single/chain; Escape closes. This local preview does not send
gameplay commands or replace the authoritative network test. `--body-capture`
runs one cycle, saves disposable frames, prints `WARRIOR_BODY_RENDER_OK` and exits.

Native Windows/Vulkan Mobile inspection of the pre-follow-up baseline confirms that the 0.6 m BODY gives a
small margin around the dog rather than a large wall; the finisher displaces it
before the Warrior can continue forward. Subjective combat feel in the normal
CEF client still requires a human playtest. Known engine/extension resource
teardown warnings remain separate from successful contract markers.

Pre-follow-up baseline checks: `git diff --check`, the default smoke
(10 Godot cases and 74 Web
contracts), ACTION with two clients, FEEL2, CombatTrace geometry/broadphase plus
50/100-mob network cases, and the existing combat network suite. Suites used
their shared fixture port sequentially. FEEL2/combat also printed their existing
RPC-after-disconnect shutdown diagnostics; passing contracts do not imply clean
fixture teardown. Native capture exited successfully on Vulkan Mobile.

For this edge-case follow-up, local checks passed: `git diff --check`, default
smoke, ACTION with both new cases, FEEL2 and the existing combat network suite.
The network suites ran sequentially. The prior native capture and 50/100-mob
trace stress runs were not repeated for this correction.
