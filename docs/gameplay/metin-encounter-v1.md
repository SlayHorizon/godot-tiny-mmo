# Metin Encounter v1

One concrete Metin lifecycle on the first region graybox, not a generic encounter
framework. World is authoritative over site, HP, threshold crossings, contributions,
wave actors, reward claim and respawn. Clients render combat snapshots. No Web UI
commands or database tables are added.

## Definition and lifecycle

`source/common/gameplay/encounters/metin/first_metin.tres` configures 800 HP,
90-second respawn, 180-second wave lifetime and a 300 Yang reward. Its three wave
resources define threshold, shared `MobSpawnEntry` composition and spawn radius:

| Remaining HP | Wave |
| --- | --- |
| 75% | 3 dogs |
| 50% | 4 dogs |
| 25% | 3 dogs + 1 elite |

Counts and combat profiles are provisional. Elites use the same dog presentation
with a distinct name/HP/damage profile. Stone presentation is a purple graybox
prism with its own nameplate and HP, not a final model. It has an attack collider
and does not block walking/navigation in this first version.

The server randomly selects one of the region's four Metin sites at startup and
each respawn; consecutive selections may use the same site. Exactly one stone is
active. `SPAWNED -> ACTIVE -> DEAD -> COOLDOWN -> SPAWNED` creates a fresh
`stone_instance_id`, clears contributions/crossings/reward state and restores HP.
The ID is runtime identity, not a durable per-kill record. World restart resets
encounter/ground entities, consistently with the current mob/ground loot policy.

`MetinRuntime` holds the state and returns newly crossed waves/death result;
`MetinEncounter` applies those results to the shared world. A large hit crossing
several thresholds triggers all of them once, including a lethal hit. Wave positions sample a disk around the stone via the shared pack spawner.
The authored sites lie on the graybox floor; server physics resolves XYZ.
Stone damage/wave spawning no longer depend on navigation synchronization.

Wave mobs retain `source_metinstone_id`, use shared [pack AI](mob-packs-v1.md) and never
respawn. They remain after stone death; each expires 180 seconds after creation.
Killed wave actors are removed after the existing death-display interval. Server
snapshots create/remove dynamic actors on clients, including for late joins.
Older surviving waves remain independently tagged if another stone respawns.

## Combat and rewards

Existing sequence validation, runtime attack stat, combo timing, range, facing
cone and scenery line-of-sight govern damage. A stone is a separate collider/domain,
not a mobile dog with extra HP. Melee can hit the stone and nearby dogs in the same
swing. LMB selection and F autoattack can assist against the stone; Space remains
untargeted directional melee. No target/damage list is accepted from clients.

Contributions count actual damage capped to remaining HP. Highest total damage
wins the reward; ties use the smaller persistent character ID. This is the existing
solo rule, not a party policy. Disconnected contributors retain their ownership
until reservation expires; reconnect uses their persistent character ID.

Death claims the reward once in RAM before delivery: one existing ground sword
and a 300 Yang pile, with normal reservation, expiry and pickup validation. There
is no direct inventory grant and no stone XP reward in this version. Wave dogs
retain ordinary dog loot/XP. Item pickup creates the persistent ItemInstance in
an immediate transaction; Yang pickup updates the existing RAM wallet/pending delta.
No persistent encounter/kill receipt or new economy batching is introduced.

## Checks and manual playtest

- `./tests/run-metin.ps1`: small runtime contracts for invalid damage, exact/multiple
  threshold crossings, capped contribution, tie-break, one reward and fresh respawn.
- `./tests/run-metin-network.ps1`: optional two-client production WebSocket/graybox
  test on port 18098 with disposable SQLite. Real attack RPCs, duplicate sequences,
  waves, shared contribution, one ground reward, reserved competing pickup and
  persistent UID, client actor removal and stone respawn. Run PvE runners sequentially.
- Existing smoke and combat runners cover the reused persistence/melee flows.

Headless verification does not establish visual feel or the 10–15 minute pacing
loop. Restart World and client, find the active purple stone on a marked pad,
watch HP thresholds/nameplates, fight waves and collect the reward. Try two
players and a late join/reload during a wave; wait for cooldown. Judge travel
length, open spaces, sightlines and reasons to detour only after this encounter
has been played. Next: spawn/pacing pass, then visual pass. Regional pressure and
party reward policies remain later, explicit work.
