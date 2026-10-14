# Mob packs and straight-line AI v1

World owns all mob spawning, runtime IDs, XYZ movement, targeting, HP, death and
replacement. This is a focused mob runtime, not a generic actor or encounter factory.
The Metin lifecycle, reward/contribution rules and persistence policy stay intact.

## Content and authoring

`source/common/gameplay/mobs/` contains `MobDefinition`, `MobSpawnEntry`,
`MobSpawnPoint3D` and the map-local `MobPackRuntime`. Four `.tres` definitions
hold the former Wild Dog, Feral Dog, Hollow Hound and Metin Elite profiles.
`mob_key` is content identity; `display_name` is presentation text. All four
currently use the optional `stray_dog` visual. HP/damage/speed/visual are copied
through one `CombatEndpoint3D.spawn_mob` entry point. `MobSpawnEntry.valid()` requires
the exact canonical resource registered in `MobDefinitions`, not merely a valid
resource with a matching key. Unregistered keys and duplicate resources using an
existing key are rejected before any pack member is spawned, including in release
builds. Register new definitions and reference those same resources in map/wave
content; runtime encounter copies must preserve their shared mob definitions.

A map authors Marker3D nodes with the `MobSpawnPoint3D` script. Each supplies
`members: Array[MobSpawnEntry]`, spawn/wander/leash radii and a per-member respawn
interval. Counts are 1–100 per entry. Invalid content is rejected at load. Spawn
and wander sample a uniform disk around the anchor, with independent timers.
No separate MobPackDefinition, leader or formation system is introduced.

The production graybox authors six pack markers in `first_region_3d.tscn`:

| Area | Pack compositions | Total |
| --- | --- | --- |
| Outskirts | 10 Wild Dogs; 10 Wild Dogs + 4 Feral Dogs | 24 |
| Old Road | 10 Wild Dogs + 6 Feral Dogs; 10 Wild Dogs + 8 Feral Dogs | 34 |
| Stone Hollow | 14 Feral Dogs + 8 Hollow Hounds; 14 Feral Dogs + 10 Hollow Hounds | 46 |

There are 104 open-world actors before Metin waves. These are density test data,
not final balance. Spawn radius is 5–6 m, wander 9–10 m, leash 15–18 m and each
killed member is replaced after 15 seconds. The hub is outside the wander +
proximity aggro envelope. Map code contains geometry, not mob combat stats.

## Runtime behavior

One combat-owned allocator issues all `mob_instance_id` and `pack_instance_id`
values for the map lifetime. The existing `mob_id` property is a runtime-ID alias
for combat/target consumers. IDs are never DB identities and are not reused.
A spawn point keeps its pack identity; each replacement gets a new actor ID.

Melee, including a killing hit, recruits the
living pack on the attacker. Dead/disabled actors are excluded. Other packs do
not inherit the target. Aggro refuses a target already outside that pack's leash.
Dog definitions disable `proximity_aggro`: walking nearby does not start combat.
Other future definitions can opt into natural proximity detection.
Members move independently: `IDLE -> WANDER`, `CHASE -> ATTACK`, `RETURN`, `DEAD`.
Chase and return use straight XZ directions, without NavigationAgent3D, navigate
or periodic repathing. Wander chooses a local point, moves and waits with jitter.
Leash compares both the member and its target against the shared pack anchor.
Return picks a separate destination per member inside the pack wander disk, once
on entering RETURN. It restores HP, clears contribution/target and resumes
idle/wander there; members do not collapse onto the anchor.

Movement still uses server gravity, floor contact and move_and_slide. Ground
bodies expose bits 1 + 5 (`17`): bit 1 remains the player's scenery/camera/NPC
navigation geometry; bit 5 (`16`) is floor-only movement for mobs. Walls/props
expose bit 1 only. Player mask remains 1, mob movement mask is 16, and mob hurtboxes
remain bit 3 (`4`). Mobs can pass through props; melee/attack line-of-sight still
uses scenery. New terrain must expose the floor bit. There is no client Y authority.
Shared navmesh baking remains for NPC approach; mobs do not query it.

Death schedules one replacement ticket containing the definition and due time.
Other members stay alive. Corpse cleanup and respawn timers are independent;
cleanup removes the old actor, and the ticket creates a fresh actor at a random
spawn point. Pack state and all timers are RAM-only. Scene teardown drops them.

## Metin and replication

`MetinWaveDefinition.members` uses the same entry resources. The 75/50/25 waves
still contain 3 Wild Dogs, 4 Wild Dogs, then 3 Wild Dogs + 1 Metin Elite.
Each wave creates its own runtime pack, immediately aggroed on the stone attacker
regardless of passive proximity policy, through the same entry point, tagged with
`source_metinstone_id`, no replacements and the existing 180-second lifetime.
Surviving waves remain after stone death and expire independently, including when
a later stone is active. Empty temporary packs are removed. There is no navmesh
synchronization requirement for stone damage or wave creation.

Snapshots still use the existing transport. The 104-actor join burst exceeded
Godot's default WebSocket buffer, so the common endpoint configures bounded 1 MiB
inbound/outbound buffers before connecting on both client and server. The network
fixtures use that same setup. This is capacity configuration, not snapshot/AOI
redesign; it increases per-connection buffer capacity. The engine properties are
listed in [Godot's WebSocketMultiplayerPeer API](https://docs.godotengine.org/en/stable/classes/class_websocketmultiplayerpeer.html).

The full snapshot now carries `mobs` as an array of compact records:

```text
[instance_id, position, yaw, hp, numeric_state, mob_key, source_metinstone_id, down_remaining_ms, get_up_remaining_ms]
```

`MobSnapshot.Field` defines the indices. `MobSnapshot.State` defines stable wire
values: IDLE=0, WANDER=1, CHASE=2, ATTACK=3, RETURN=4, DEAD=5, DISABLED=6.
Server AI continues using its existing names internally. The shared
`MobDefinitions.resolve(mob_key)` registry supplies client display name, maximum
HP and visual ID. Register new content in that registry before spawning it;
unknown keys are warned about once per key for the endpoint lifetime and skipped
rather than rendered with fake metadata.
Client and server content/protocol must ship together; the old dictionary shape
is not supported.

Damage, speed, home/pack anchor, pack ID, leash, aggro and respawn state are not
replicated. The source stone ID remains for encounter provenance/debugging.
World actors contain no DogVisual or name/HP Label3D nodes and do not format label
text during physics ticks. Clients create new actors from the current position, remove missing ones (including
an empty full snapshot), and interpolate. They do not spawn, wander, leash or
respawn. The target resolver clears dead/removed identities and disables autoattack;
a replacement cannot revive an old selection. Transport, cadence, full-snapshot
semantics and 1 MiB buffers remain unchanged. AOI, deltas and split RPCs are deferred.

### Serialized payload measurement

`mob_packs.gd` compares the frozen previous dictionary shape with the production
compact encoder for the same actors using Godot `var_to_bytes`. These numbers
measure only the complete `dogs`/`mobs` section, including its outer dictionary;
they exclude other combat fields, RPC framing and WebSocket overhead.

| Actors | Previous | Compact | Reduction |
| --- | --- | --- | --- |
| 50 | 20,108 bytes / 19.64 KiB | 4,904 bytes / 4.79 KiB | 75.6% |
| 100 | 39,908 bytes / 38.97 KiB | 9,704 bytes / 9.48 KiB | 75.7% |

Measured headlessly with Godot 4.7.2 on Windows. This is roughly a 4.1x reduction
including the two reaction recovery fields for this fixture, not a total bandwidth or frame-time benchmark. Names, source
IDs and composition affect byte counts. The regression check requires a broad
reduction, not these exact numbers.

## Verification and remaining manual pass

Default smoke includes `mob_packs.gd`: mixed composition, ID uniqueness, pack-only
aggro/proximity, anchor leash/reset, one member's replacement, old-target invalidation,
Metin provenance/expiry, a short 50-actor AI tick, compact serialization round trips
(including every AI state) and 50/100-actor payload sizes. This is not a benchmark.
`run-first-region`, `run-metin`, `run-combat` and `run-metin-network` cover production
content, stone thresholds, collision policy, real melee pack aggro and two-client
snapshot/reward behavior. Test fixtures use the small legacy arena where appropriate.

Restart World and reconnect clients to load the new data/protocol. Play 10–15 minutes:
attack one outskirts member, pull the pack, kill several, leave leash, return and
observe individual replacements; continue through mixed packs and a Metin wave.
Assess density, readable combat, travel gaps and client frame time. Headless checks
do not prove native render performance at 104 actors. No balancing or additional AI
framework should precede that manual pass.
