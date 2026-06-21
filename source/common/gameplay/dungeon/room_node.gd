class_name RoomNode
extends Area2D
## A dungeon ROOM encounter. Place it in the dungeon map with a CollisionShape2D
## covering the room's floor, and add SpawnMarker children for its mobs. When the
## WHOLE party has stepped inside, the encounter activates: it spawns the markers'
## mobs (as dynamic props, so clients see them) and tracks them; once every mob is
## dead the room is CLEARED. The final room's clear ends the whole dungeon.
##
## Server-authoritative — the encounter logic runs only on the world server; the
## mobs sync themselves and the door SEAL is pushed to every client (see
## _push_seal — movement is client-authoritative, so the collision change must
## happen on each client).

## Beat between sealing the room and the mobs materializing — the "doors slam, here it comes"
## telegraph reads far better than an instant pop.
const SPAWN_DELAY_S: float = 0.7

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


## Seal the encounter: spawn every SpawnMarker child's mob and start tracking them.
func _activate() -> void:
	var map: Node = get_parent()
	var container: ReplicatedPropsContainer = map.replicated_props_container if map != null else null
	if container == null:
		push_warning("RoomNode '%s': map has no ReplicatedPropsContainer — no mobs." % name)
		return
	# Seal the party in FIRST, then a short beat before the mobs materialize — the "doors slam,
	# here it comes" telegraph reads far better than spawning the instant the trigger fires.
	_push_seal(true)
	await get_tree().create_timer(SPAWN_DELAY_S).timeout
	if not is_instance_valid(self) or not is_inside_tree():
		return # instance torn down during the beat (party wiped / disconnected)
	var instance: Node = map.get_parent() # RoomNode → Map → ServerInstance
	var hard: bool = DungeonService.is_hard_run(instance)
	# Hard-mode multipliers come off the dungeon's resource (fall back to the
	# service defaults if it isn't a DungeonResource).
	var dres: DungeonResource = instance.instance_resource as DungeonResource if instance != null else null
	var hp_mult: float = dres.hard_health_mult if dres != null else DungeonService.HARD_HEALTH_MULT
	var dmg_mult: float = dres.hard_damage_mult if dres != null else DungeonService.HARD_DAMAGE_MULT
	for child: Node in get_children():
		if child is SpawnMarker and (child as SpawnMarker).enemy_type != null:
			var marker: SpawnMarker = child
			var mob: Node = container.spawn_dynamic(
				ReplicatedPropsContainer.SCENE_HOSTILE_NPC,
				container.to_local(marker.global_position),
				{"enemy_type_slug": _slug_of(marker.enemy_type)}
			)
			if mob != null:
				# Boss = the marker says so OR the enemy type is itself a boss (so a
				# dungeon_boss just works, no per-marker flag to forget).
				var npc: HostileNpc = mob as HostileNpc
				var is_boss: bool = marker.boss \
						or (npc != null and npc.enemy_data != null and npc.enemy_data.is_boss)
				make_dungeon_mob(mob, is_boss)
				if hard and npc != null:
					npc.apply_difficulty(hp_mult, dmg_mult)
				if is_boss and npc != null:
					var brain: BossController = BossController.new()
					brain.boss = npc
					npc.add_child(brain) # _ready() loads slam_damage from enemy_data...
					if hard:
						brain.slam_damage *= dmg_mult # ...so scale it AFTER that load
				_alive += 1
				mob.died.connect(func(_killer: Character) -> void: _on_mob_died())
				if npc != null:
					# Client fade/scale-in. An OP (not spawn init — the wire drops init), so it
					# lands on the prop after it exists on every client. See docs.
					npc.replicate_visual(&"rp_materialize", [])
	if _alive == 0:
		_clear() # empty encounter authored — clear immediately


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
	if map == null or instance == null or ServerHub.current == null:
		return
	var paths: Array = []
	for door: ActivableDoor in doors:
		if door != null:
			paths.append(String(map.get_path_to(door)))
	ServerHub.current.propagate_rpc(
		ServerHub.current.data_push.bind(&"dungeon.room", {"doors": paths, "sealed": sealed}),
		instance.name
	)


## The registry slug for an enemy type (== its metadata/slug, which equals its
## enemy_type identifier by convention).
static func _slug_of(enemy_type: EnemyTypeResource) -> StringName:
	return enemy_type.get_meta(&"slug", enemy_type.enemy_type)
