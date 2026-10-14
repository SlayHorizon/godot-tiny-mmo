# Warrior Combat Trace v1

Warrior one-handed basic combo uses actor-local baked blade geometry instead of
the generic sphere/cone. World loads seven small `CombatTraceDefinition` resources
(about 18.7 KiB total), never the GLB, AnimationPlayer, Skeleton3D or weapon bones.
The client still sends only `request_attack(sequence)`. Damage, reactions and
finisher displacement remain in the accepted `BasicAttackStepDefinition`.

## Bake source and coordinate contract

The inspected local source is `dev_assets/legacy/players/warrior/warrior_all_motions.glb`
(SHA256 `23434ccff5098c81a5167d863e73e57308e6f9398a6629473b5e85f3f3db4adc`).
The actual rig is `Warrior/Bip01/Skeleton3D`; the production `SwordSocket` is a
BoneAttachment3D bound to `equip_right_hand`. The separate iron sword is attached
under that socket, with the existing grip correction and centimetre/metre scale
compensation. The tool uses the production Warrior presentation adapter, including
its in-place private clips; it does not invent a second attachment transform.

Base is the equipped weapon origin. Tip is origin plus its transformed, normalized
local +Y axis times **1.3 m**: original MSA WeaponLength is 130 cm. No mesh vertices
or AABB define gameplay length. Both endpoints are converted with `view.to_local()`
to Warrior actor-root coordinates. An offline assertion changes preview translation
and yaw and confirms that the local endpoints do not change.

Only ten samples per active window are stored; no per-frame animation data. Radius
is 0.20 m. The configuration is `tools/combat/warrior-trace-bake.json`.

| Clip suffix | Active start/end (ms) | Effective impact (ms) |
| --- | ---: | ---: |
| 01 | 192–315 | 260 |
| 02 | 215–321 | 270 |
| 03 | 181–418 | 290 |
| 04 | 570–700 | 620 |
| 05 | 346–494 | 410 |
| 06 | 324–587 | 420 |
| 07 | 570–700 | 620 |

01/02/05/06 use rounded MSA attack windows. 03's native window ends at 522 ms;
it is clipped at its existing 418 ms link/recovery so no geometry is borrowed from
after the next accepted step. 04/07 have zero/missing ordinary attack windows;
570–700 ms is an explicit initial gameplay window around the tuned imported-clip
impact, not a value claimed to come from MSA. These two windows still need a human
contact-feel pass. Recovery and reaction content did not change in this slice.

Bake from the repository root (requires the existing local development assets):

```powershell
& ./tools/combat/bake-warrior-trace.ps1
```

The wrapper checks the completion marker/script errors and stores its log in
`.godot/verification`. Review generated `.tres` changes alongside window edits.
The source GLB and reference extraction stay local/ignored; shipped gameplay
Resources contain coordinates and times only. Missing real rig/socket fails the
bake rather than silently producing traces from a procedural placeholder.

## Server resolution

At acceptance World freezes the step, yaw, start/impact timestamps and runtime
attack stat. The existing scheduler resolves once at effective impact, provided
that the current time is within the active window. It tests the complete baked
window sweep against current target positions. This is the explicitly chosen v1
single-resolution approximation, not continuous per-time-sample damage. A delayed
resolution beyond the window produces no hit.

One conservative oriented box covers all blade endpoints plus sweep radius and
padding. One `intersect_shape` broadphase returns up to **256 collider shapes**.
That is a bound, not an unlimited target count; multi-shape actors consume entries.
The box includes asymmetric gameplay Y padding, while XZ keeps the existing
radius/rail padding. World rejects fully behind and out-of-range candidates. Each
adjacent sample pair gates its XZ distance tests on defending-capsule Y overlap. The existing scenery line-of-sight ray still runs for a
geometric hit. There is no physics query for each blade sample.

Between samples, previous/current blades and nine interpolated blade rails form
a ruled sweep. Half the rail spacing is added as conservative padding (about
0.081 m for a 1.3 m blade), preventing holes in the swept interior. This can admit
slightly generous edge hits; it is deliberately not mesh collision or an exact
rotational continuous solver. XZ bounds include the same rail padding; Y bounds use blade radius and the
separate vertical allowances.

Target gameplay capsules read radius, height and bottom offset directly from
current authoritative upright, unscaled colliders: player 0.35/1.8 m, dog 0.4/0.8 m,
stone 0.7/2.8 m. Bottom offset is collider Y minus half its height; these values
are not separately configured in the attack resolver. Visual meshes are never queried. Basic melee rejects
a target wholly behind the actor even if a wind-up passes behind its back.

Each accepted swing has a hit set, keyed by actor identity. Extra collider shapes
or many intersecting samples cannot repeat damage. A resolved swing cannot run
again. Surviving targets continue through the existing HitReactionResolver and
profile-scaled physical finisher knockback. Metin stones use their encounter damage
path and remain immovable. Mob/boss attacks and other classes are unchanged.

## Fallback and developer review

A step without `combat_trace` uses the retained sphere/cone resolver. Its query
also permits 256 shapes instead of the former 64. For a local editor-engine World,
append `-- --dev-legacy-melee` to force accepted basic steps onto that fallback;
this is a process-local development option, never a client command or RPC.

For server logs append `--combat-trace-metrics` in the user arguments. Logs show
path, candidate shape count, trace-test count, hits and total resolve microseconds.
For a development client append `--combat-trace-debug`: yellow literal blades,
cyan sweep rails/radius rings, translucent vertical prisms, blue broadphase bounds,
target capsule outlines and green authoritative hits use the very same shared Resources. Overlay yaw/positions are sampled from
client presentation at swing receipt; this is a debug approximation of the frozen
server transform, not another source of hit authority.

Focused native preview:

```powershell
& ./.godot/Godot_v4.7.2-stable_win64.exe --path . --mode=client res://tests/warrior_compatibility.tscn -- --require-dev --preview --combo-review --trace-review
```

1/2/3 select the 4/5/6-hit chain. T switches trace/cone outlines and recomputes
predicted target hits; B toggles attack blend 0/0.08. V toggles Warrior variant;
H switches the preview defender between a real dog and Warrior with their current
capsule dimensions. It is placed in front of the right-hand reviewer so narrow
04 can be reviewed alongside the wide sweeps. Esc closes. Optional `--trace-pack=50` adds simulated capsule targets and geometry
measurements, not fifty simulated AI actors. Real-game debug coloring instead uses
server hit results. The preview does not authorize damage or simulate knockback.

## Verification and limits

```powershell
& ./tests/run-combat-trace.ps1
& ./tests/run-combat.ps1
& ./tests/run-combat.ps1 -LegacyMelee
```

The trace suite is opt-in, keeping default smoke small. It covers front hit, side,
behind and height misses, an interior hit between samples, transformed actor roots,
valid finite baked samples/windows, 100 real broadphase targets plus an extra
collider shape, and two-client production damage with baked 01 for 50/100 targets.
The network case checks one damage per target, repeat-swing rejection, out-of-window
rejection, authoritative observer state and no-trace fallback. Existing four/six-hit
network combat also passes on trace and legacy paths, including finisher locks,
physical displacement and pending swing interruption. The six-hit fixture puts its
finisher targets in front of the actual blade rather than assuming cone-wide reach.
Metin encounter network, Warrior development/placeholder checks and default smoke
passed. No pixel, timing or performance benchmark gate was added to CI.

On this Windows/RTX 4070 development machine, a representative run measured about
4.4 ms for 50 and 6.1 ms for 100 targets in the full server resolve fixture (including
LOS/damage/RPC work). Native preview's 50 geometric tests were roughly 1–3 ms per
variant/step. These are rough local observations, not stable benchmark thresholds.
Native Vulkan Mobile captures show all 4/5/6 chains with baked trajectory overlays,
including the broad 01 sweep and narrower downward 04. Assets/animation were not
re-exported. Existing extension teardown ObjectDB/resource warnings remain.

Continuous human comparison of contact feel and a live 20–50 mob fight's CPU/render
behavior remains outstanding. Native impact frames and headless assertions do not
prove that subjective acceptance criterion. Keep the legacy path until that pass;
especially tune authored 04/07 windows and sweep edge tolerance if necessary.

## Local test assistance

`tools/servers.ps1 -Action restart -Target world -DevCombat` enables local World
god mode and a practice sword grant on character entry. The ignored runtime marker
preserves this choice across launcher restarts. Use `-DisableDevCombat` with a
World restart to restore ordinary damage and stop grants. Flags are server-local
and editor-engine only; no client God Mode/grant RPC is exposed. God mode blocks
HP damage, action locks and displacement for every character on this local World.

Practice sword is a separate persistent, two-cell item using the existing sword
icon/visual. Grant + placement commit atomically, and an already owned copy prevents
a new grant on relog. A full bag fails cleanly; clear two adjacent cells and relog.
Its explicit test-content stat rule sets total attack to 1 when equipped rather
than adding 1 to base character attack 10. Unequip restores ordinary stats; no
upgrade recipe accepts it. Normal combat stats/equipment behavior is unchanged.

Development clients can toggle trace overlays with **F8** during gameplay.
An ignored `.godot/runtime/trace-debug.enabled` marker enables initial overlays
for a native local client. CLI `--combat-trace-debug` remains available. Turning
it off frees overlays immediately; turning it on draws the next swing. Client
restart is required to load changed scripts; no native window is launched by tests.

## Vertical forgiveness v1

Shared defaults on `CombatTraceDefinition` are **0.9 m down / 0.3 m up** for all
seven clips. They are gameplay tuning, not animation-derived or final balance.
Neither baked endpoints nor bake tools, impact/window timings, playback, damage,
reactions or knockdown change. No target-specific trace shifting or vertical aim.

For every adjacent pair, the four endpoint Y values define min/max, expanded by
blade radius, then by the asymmetric allowances. This interval must overlap
`actor Y + bottom_offset .. actor Y + bottom_offset + height`. Only then are the
same blade edges and nine rails projected onto XZ and tested against the target
capsule's horizontal circle. Vertical padding cannot widen XZ or borrow overlap
from an unrelated segment elsewhere in the sweep. The broadphase remains one box
query per swing (maximum 256 shapes), now covering the complete vertical extrusion.

Debug keeps the literal blades at their baked heights. Translucent prisms show the
swept blade footprint and its gameplay Y interval; blue wire bounds additionally
show conservative broadphase radius/rail padding. This is a diagnostic sweep view,
not final combat VFX. Target capsules include their collider-derived bottom offset.

The focused trace tests cover a high blade missing a low dog without padding and
hitting with defaults, humanoids, small downward differences, behind/side/range
misses, far-below/above misses, bottom offsets, per-pair interval isolation, invalid
padding, unchanged horizontal bounds, and an actual query that finds 100 low bodies
only after Y extrusion. Network coverage adds an unmodified baked 02 against 50
low dogs with one damage each, duplicate shapes, repeated-swing rejection and
out-of-range exclusions. The old combat fixture's lateral miss is now explicitly
outside the full projected sweep rather than depending on literal blade height.

Default smoke, focused trace/two-client damage, four/six-hit combat, and Metin
encounter/network checks passed. Native Vulkan Mobile captures review 01/03/04 with
dog and Warrior-sized defenders, separating blade geometry from vertical allowance.
These frame checks establish rendering, not a continuous human judgement of feel;
the live fight/manual contact-feel pass remains open. Tune the shared allowance
first if high hits look excessive, rather than adding animation-specific exceptions.

To reproduce a single automatic native render review (local development assets):

```powershell
& ./.godot/Godot_v4.7.2-stable_win64_console.exe --path . --mode=client res://tests/warrior_compatibility.tscn -- --require-dev --preview --combo-review --trace-review --vertical-capture
```

It captures the four-hit chain once per defender type under `.godot/verification`
and exits. This remains an optional manual milestone tool, outside default smoke.
