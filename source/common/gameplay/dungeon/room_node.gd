class_name RoomNode
extends Area2D
## A dungeon ROOM encounter. Place it in the dungeon map with a CollisionShape2D
## covering the room's floor, and add SpawnMarker children for its mobs. When the
## WHOLE party has stepped inside, the encounter activates: it spawns mobs WAVE BY
## WAVE (markers grouped by SpawnMarker.wave — clear one wave before the next
## appears; default all-0 = a single pack) and tracks them; once the LAST wave is
## dead the room is CLEARED. The final room's clear ends the whole dungeon.
##
## Server-authoritative — the encounter logic runs only on the world server; the
## mobs sync themselves and the door SEAL is pushed to every client (see
## _push_seal — movement is client-authoritative, so the collision change must
## happen on each client).

## Beat between sealing the room and the first wave spawning — the "doors slam, here it comes"
## telegraph. Editable per room in the inspector.
@export var spawn_delay_s: float = 0.7
## Beat between clearing one wave and the next spawning — a breath of "more coming" tension.
@export var wave_delay_s: float = 1.2

## The last room — clearing it clears the dungeon (pushes dungeon.cleared). The
## reward lives on the run's DungeonResource now, not here.
@export var final_room: bool = false
## Doors this room SEALS when the encounter starts and OPENS when it clears (e.g.
## the gate onward). Author them as ActivableDoor nodes anywhere in the map, set
## their starts_open = true (so the party can walk in before the seal), and list
## them here.
@export var doors: Array[ActivableDoor] = []

var _activated: bool = false
var _cleared: bool = false
var _alive: int = 0
## peer_id -> currently inside the room trigger.
var _inside: Dictionary[int, bool] = {}
## SpawnMarker children grouped by their `wave` (index = wave number); built on activate.
var _waves: Array[Array] = []
var _current_wave: int = 0
var _container: ReplicatedPropsContainer
## Hard-mode multipliers, resolved once on activate + reused for every wave.
var _hard: bool = false
var _hp_mult: float = 1.0
var _dmg_mult: float = 1.0


func _ready() -> void:
	# Detect player bodies (collision layer 1) walking in/out.
	if not GameMode.is_world_server():
		return
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node2D) -> void:
	if _activated or body is not Player:
		return
	_inside[body.name.to_int()] = true
	if _whole_party_inside():
		_activated = true
		# Deferred: we're inside a physics callback (body_entered). Spawning a mob
		# now toggles collision shapes mid-flush — "Can't change this state while
		# flushing queries". Let the frame's physics finish first.
		_activate.call_deferred()


func _on_body_exited(body: Node2D) -> void:
	if body is Player:
		_inside.erase(body.name.to_int())


## True when EVERY living player in this (private) instance is inside the room —
## the "wait for the whole party" gate. Dead/respawning members don't block it.
func _whole_party_inside() -> bool:
	var instance: Node = get_parent().get_parent() # RoomNode → Map → ServerInstance
	if instance == null:
		return false
	var present: int = 0
	for peer_id: int in instance.players_by_peer_id:
		var player: Player = instance.players_by_peer_id[peer_id]
		if player == null or player.is_dead:
			continue
		present += 1
		if not _inside.get(peer_id, false):
			return false # someone living is still outside
	return present > 0


## Activate the encounter: seal the party in, beat, then spawn the FIRST wave. Mobs come wave by
## wave — each must be cleared before the next appears (SpawnMarker.wave groups them; default 0 =
## one wave, the classic single pack). The room clears when the LAST wave is down.
func _activate() -> void:
	var map: Node = get_parent()
	_container = map.replicated_props_container if map != null else null
	if _container == null:
		push_warning("RoomNode '%s': map has no ReplicatedPropsContainer — no mobs." % name)
		return
	_resolve_difficulty(map)
	_build_waves()
	# Seal the party in FIRST, then a short beat before the first wave — the "doors slam, here it
	# comes" telegraph reads far better than spawning the instant the trigger fires.
	_push_seal(true)
	await get_tree().create_timer(spawn_delay_s).timeout
	if not is_instance_valid(self) or not is_inside_tree():
		return # instance torn down during the beat (party wiped / disconnected)
	_spawn_wave(0)


## Hard-mode HP / damage multipliers off the run's DungeonResource (service defaults otherwise),
## resolved once so every wave scales identically.
func _resolve_difficulty(map: Node) -> void:
	var instance: Node = map.get_parent() if map != null else null # RoomNode → Map → ServerInstance
	_hard = DungeonService.is_hard_run(instance)
	var dres: DungeonResource = instance.instance_resource as DungeonResource if instance != null else null
	_hp_mult = dres.hard_health_mult if dres != null else DungeonService.HARD_HEALTH_MULT
	_dmg_mult = dres.hard_damage_mult if dres != null else DungeonService.HARD_DAMAGE_MULT


## Group SpawnMarker children into _waves by their `wave` index (0,1,2…); markers without an enemy
## type are skipped. _waves[w] is the (possibly empty) list of markers for wave w.
func _build_waves() -> void:
	_waves = []
	var max_wave: int = 0
	for child: Node in get_children():
		if child is SpawnMarker and (child as SpawnMarker).enemy_type != null:
			max_wave = maxi(max_wave, (child as SpawnMarker).wave)
	for _i: int in max_wave + 1:
		_waves.append([])
	for child: Node in get_children():
		if child is SpawnMarker and (child as SpawnMarker).enemy_type != null:
			_waves[(child as SpawnMarker).wave].append(child)


## Spawn every mob in wave [param n] (resetting the alive count for it), or clear the room if there
## are no more waves. An empty wave (a gap in the numbering, or one that spawned nothing) advances
## immediately so it can't stall the room.
func _spawn_wave(n: int) -> void:
	_current_wave = n
	if n >= _waves.size() or not is_instance_valid(_container):
		_clear()
		return
	_alive = 0
	for marker: SpawnMarker in _waves[n]:
		_spawn_marker_mob(marker)
	if _alive == 0:
		_advance_wave()


## Spawn + configure one marker's mob: dungeon overrides, hard-mode scaling, the boss brain, the
## summon burst + freeze, and death tracking for the current wave.
func _spawn_marker_mob(marker: SpawnMarker) -> void:
	var mob: Node = _container.spawn_dynamic(
		ReplicatedPropsContainer.SCENE_HOSTILE_NPC,
		_container.to_local(marker.global_position),
		{"enemy_type_slug": _slug_of(marker.enemy_type)}
	)
	if mob == null:
		return
	# Boss = the marker says so OR the enemy type is itself a boss (so a dungeon_boss just works).
	var npc: HostileNpc = mob as HostileNpc
	var is_boss: bool = marker.boss \
			or (npc != null and npc.enemy_data != null and npc.enemy_data.is_boss)
	make_dungeon_mob(mob, is_boss)
	if _hard and npc != null:
		npc.apply_difficulty(_hp_mult, _dmg_mult)
	if is_boss and npc != null:
		var brain: BossController = BossController.new()
		brain.boss = npc
		npc.add_child(brain) # _ready() loads slam_damage from enemy_data...
		if _hard:
			brain.slam_damage *= _dmg_mult # ...so scale it AFTER that load
	_alive += 1
	mob.died.connect(func(_killer: Character) -> void: _on_mob_died())
	if npc != null:
		# Summon burst + brief hold so the mob phases in, not pops + instantly attacks.
		npc.action_root_until_ms = Time.get_ticks_msec() + int(HostileNpc.SPAWN_FREEZE_S * 1000.0)
		npc.replicate_visual(&"rp_spawn_effect", [])


## Force DUNGEON behavior on a freshly-spawned mob regardless of its enemy type:
## never respawn (single-life), never leash (commit to the fight), and — unless
## it's the boss — drop nothing (the payoff is completing the dungeon, not farming
## trash). Server-side overrides applied after the spawn's _ready. NB: replace the
## loot array with a fresh one — never clear it in place, it's shared with the
## EnemyTypeResource. Shared with BossController (it stamps its summoned adds).
static func make_dungeon_mob(mob: Node, is_boss: bool) -> void:
	mob.respawns = false
	mob.max_distance_from_spawn = HostileNpc.NO_LEASH_DISTANCE
	if not is_boss:
		mob.xp_reward = 0
		var no_loot: Array[LootDrop] = []
		mob.loot = no_loot


func _on_mob_died() -> void:
	_alive -= 1
	if _alive <= 0:
		_advance_wave()


## The current wave is cleared: spawn the next after a short beat, or clear the room if that was the
## last wave. Async (the inter-wave beat) — fine, it's fired from a death callback.
func _advance_wave() -> void:
	if _current_wave + 1 < _waves.size():
		await get_tree().create_timer(wave_delay_s).timeout
		if not is_instance_valid(self) or not is_inside_tree():
			return
		_spawn_wave(_current_wave + 1)
	else:
		_clear()


## Room cleared — open the way onward. The FINAL room ends the whole run:
## DungeonService shows the recap + auto-ejects the party after a timer.
func _clear() -> void:
	if _cleared:
		return
	_cleared = true
	_push_seal(false) # open the way onward
	if final_room:
		var instance: Node = get_parent().get_parent() # RoomNode → Map → ServerInstance
		if instance != null:
			DungeonService.on_dungeon_cleared(instance) # reward read off the run's resource


## Tell every client in this instance to seal (or open) this room's doors.
## Movement is client-authoritative, so the collision change has to happen on each
## client — we push the door node PATHS (relative to the map; the authored doors
## already exist on every client) and let the clients toggle them. No prop baking
## or ids needed.
func _push_seal(sealed: bool) -> void:
	if doors.is_empty():
		return
	var map: Node = get_parent()
	var instance: Node = map.get_parent() if map != null else null
	if map == null or instance == null or WorldServer.curr == null:
		return
	var paths: Array = []
	for door: ActivableDoor in doors:
		if door != null:
			paths.append(String(map.get_path_to(door)))
	WorldServer.curr.propagate_rpc(
		WorldServer.curr.data_push.bind(&"dungeon.room", {"doors": paths, "sealed": sealed}),
		instance.name
	)


## The registry slug for an enemy type (== its metadata/slug, which equals its
## enemy_type identifier by convention).
static func _slug_of(enemy_type: EnemyTypeResource) -> StringName:
	return enemy_type.get_meta(&"slug", enemy_type.enemy_type)
