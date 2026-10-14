# First region graybox

The normal `Spike` instance now loads `first_region_3d.tscn`. Its existing instance
identity stays stable for sessions, NPC authorization and persistence. The old
32 m arena remains a network-test fixture; it is no longer the login destination.
Restart World and reconnect the client to load the new scene.

## Authored region

World units are metres. The region envelope is 96 × 144 m: X -48..48,
Z -108..36. Walkable land ends at X 26; the eastern strip is a flat water/material
placeholder behind a low collision boundary. There is no swimming or water shader.
The hub is at the southern end (+Z). Default camera forward faces north (-Z).

| Area | Centre X / Z | Current content |
| --- | --- | --- |
| Hub | 0 / 20 | Player entry/respawn, Blacksmith with existing Shop and Upgrade |
| Outskirts | -16 / -10 | Two packs: 10 / 14 members, Wild + Feral Dogs |
| Old Road | 8 / -46 | Two mixed packs: 16 / 18 members |
| Stone Hollow | -12 / -82 | Two mixed packs: 22 / 24 Feral Dogs + Hollow Hounds |

All three use the existing dog visual/AI/combat/loot/XP pipeline. Health and damage
increase by area; values are provisional and not a balance target. XP and drops
retain current behavior. Each per-member replacement retains its definition and receives a new runtime ID.
There are 104 mobs in six packs; [mob packs v1](mob-packs-v1.md) records composition,
shared aggro and anchor leash. These are provisional density data. The hub starts
outside pack wander/aggro envelopes.

A five-metre-wide main road connects the areas and loops back along the west.
A narrower direct north path and coast cut offer shortcuts. Five-metre ticks on
the north path expose world scale. Buildings, forge chimney, western watchtower,
shrine, stone arch and rock corners provide landmarks and camera collision cases.
Roads/zone tints are surface marks, not separate navigation authority.

Four visible pads and `MetinSpawn1..4` markers reserve candidate sites at
(-24,-20), (16,-44), (-20,-78), (10,-92). The pads themselves are not loot sources. [Metin Encounter v1](metin-encounter-v1.md)
selects one site for its live stone and timed respawn.
Edit geometry/routes in `first_region.gd`, pack markers/composition in
`first_region_3d.tscn`, and combat stats in the separate MobDefinition resources; no procedural
region system or generic spawn framework is introduced. Scenery is layer 1 for player movement, NPC navigation, line-of-sight and camera.
Ground additionally exposes layer 5 for mob movement, which ignores scenery.
Server instances skip the graybox meshes/labels and keep collision/markers.

## Verification and playtest

`./tests/run-first-region.ps1` loads the actual production scene headlessly and
checks shared navigation from the safe hub to Blacksmith, every pack anchor and every
Metin site, plus authored composition and a blocking shore boundary.
Default smoke covers per-member replacement and profile retention.
The test waits for navigation synchronization rather than assuming two frames.
Existing combat network fixtures keep their small arena and ownership/loot checks.
Do not turn coordinates, exact geometry, pacing or damage values into assertions.

Manual pass: leave the hub, fight the first pack, explore the road/shortcut to the
next two packs, collect loot, return to Blacksmith, and die/respawn once. Try orbit
and min/max zoom near the forge, arch, rocks and shrine. Assess travel distances,
combat room, landmark visibility and camera behavior with two clients. No native
window is automatically opened by the headless checks.

Development presenters retain their active PackedScene resources while instances
are alive. Otherwise the 250 ms model-selection polls reload weakly cached scenes.
A local headless nine-dog probe measured roughly 4 ms average / 5.1 ms maximum
before retention, versus 0.7 ms average / 1.1 ms maximum after it. This measures
CPU resource resolution only, not GPU frame time or proof that visible judder is
fixed; native movement on the region still needs comparison against the arena.

## Next slices

1. [Metin Encounter v1](metin-encounter-v1.md) is implemented at these sites;
   playtest stone combat, waves, ground reward and timed respawn.
2. Spawn/pacing pass: evaluate a 10–15 minute route, pack density, return cost and
   event cadence. The encounter now supports the loop; its pacing has not yet been manually assessed.
3. Visual pass after scale/gameplay feedback; final models, terrain and materials.

The first [lighting baseline](visual-upgrade-v1.md) is now integrated: fixed
15:30, Sky3D procedural sky/clouds, sun, AgX and light fog. The separate
[V2 calendar pass](visual-upgrade-v2.md) now animates dawn/day/sunset/night,
moon phases, stars, ambient light, exposure and haze. Geometry, routes,
collisions and gameplay authority are unchanged. This is environment tuning;
the authored ground/props remain graybox surfaces.

[V3 water](visual-upgrade-v3.md) now replaces the water material/mesh and adds a
minimal submerged visual slope for shallow/deep color. The original shore
collision and route geometry remain; coastline/terrain art is a later V4 pass.

Party, affix reroll and speculative region/event frameworks do not block this order.
Regional pressure remains a design direction; this graybox adds no pressure system.
