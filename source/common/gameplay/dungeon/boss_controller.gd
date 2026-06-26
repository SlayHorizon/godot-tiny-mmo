class_name BossController
extends Node
## The BRAIN of a dungeon boss. The boss itself stays a plain HostileNpc (the BODY:
## moves, basic-attacks, takes damage, dies); this node watches the body's HP and
## orchestrates the fight on top — phase transition, a telegraphed slam, and an
## enrage that summons adds + speeds the body up. Every move is composed from
## primitives that ALREADY exist (AttackTelegraph via the body's rp_lunge_telegraph,
## container.spawn_dynamic for summons, plain stat tweaks), so none of it bloats
## HostileNpc.
##
## RoomNode attaches one to a boss marker's mob on spawn. Server-only: it frees
## itself anywhere else (and since it's added AFTER the dynamic spawn, clients never
## receive it). Tuning is data-driven from the body's EnemyTypeResource (the vars
## below are fallbacks that mirror the resource defaults — see _load_config).

## Extra seconds the body stays planted AFTER a slam lands — sells the weight and
## stops the boss snapping straight back into a chase.
const SLAM_RECOVER_S: float = 0.25

## Enrage when the body drops to this fraction of max HP.
var enrage_at_health_fraction: float = 0.5
## Slam danger-zone: radius (px), the windup players have to leave it, and the hit.
var slam_radius: float = 110.0
var slam_windup_s: float = 1.1
var slam_damage: float = 45.0
## Seconds between slams — phase 1, then the faster enraged cadence.
var slam_interval_s: float = 6.0
var enraged_slam_interval_s: float = 3.5
## Adds summoned the moment the boss enrages.
var add_enemy_slug: StringName = &"rat_base"
var add_count: int = 2
var add_spread_px: float = 48.0
## Move-speed multiplier applied on enrage (the body chases harder).
var enrage_speed_mult: float = 1.3

## The body this brain drives. Set by the spawner before add_child.
var boss: HostileNpc

var _enraged: bool = false
var _casting: bool = false
var _next_slam_ms: int = 0


func _ready() -> void:
	if not multiplayer.is_server() or boss == null:
		queue_free()
		return
	_load_config()
	_next_slam_ms = Time.get_ticks_msec() + int(slam_interval_s * 1000.0)
	# Boss-event music is driven by the boss's own lifecycle — automatic for EVERY boss
	# (world + dungeon both attach this brain): the combat track on spawn, the victory
	# sting on death. An admin abort (boss removed WITHOUT dying) is cued as "end" by
	# EventService. Client side: Client._on_boss_music. boss.container is wired by now
	# (spawn_dynamic returned before our parent attached us), so _instance() resolves.
	push_boss_music(_instance(), "fight")
	boss.died.connect(_on_boss_died_music)


## Server → clients: a boss-event music cue (fight / victory / end) for everyone in
## [param instance]. Static so EventService can fire "end" on an admin abort too.
static func push_boss_music(instance: Node, state: String) -> void:
	if instance == null or WorldServer.curr == null:
		return
	for peer_id: int in instance.players_by_peer_id:
		WorldServer.curr.data_push.rpc_id(peer_id, &"boss.music", {"state": state})


func _on_boss_died_music(_killer: Character) -> void:
	push_boss_music(_instance(), "victory")


## Pull tuning from the body's EnemyTypeResource so each boss is configured in
## data. The var defaults mirror the resource defaults, so a boss whose .tres
## leaves the Boss group untouched behaves exactly as before.
func _load_config() -> void:
	var d: EnemyTypeResource = boss.enemy_data
	if d == null:
		return
	enrage_at_health_fraction = d.enrage_health_fraction
	slam_radius = d.slam_radius
	slam_windup_s = d.slam_windup_s
	slam_damage = d.slam_damage
	slam_interval_s = d.slam_interval_s
	enraged_slam_interval_s = d.enraged_slam_interval_s
	add_enemy_slug = d.add_enemy_slug
	add_count = d.add_count
	add_spread_px = d.add_spread_px
	enrage_speed_mult = d.enrage_speed_mult


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(boss) or boss.is_dead:
		return
	if not _enraged and _health_fraction() <= enrage_at_health_fraction:
		_enrage()
	# Only slam while someone is actually engaging — no flailing at an empty room.
	if not _casting and boss.targeted_player != null and Time.get_ticks_msec() >= _next_slam_ms:
		_slam()


func _health_fraction() -> float:
	var max_h: float = boss.stats_component.get_stat(Stat.HEALTH_MAX)
	if max_h <= 0.0:
		return 1.0
	return boss.stats_component.get_stat(Stat.HEALTH) / max_h


## Telegraph a danger ring at the boss, give players the windup to step out, then
## hit everyone still inside it. Reuses rp_lunge_telegraph — with the target point
## AT the boss, its AttackTelegraph draws a CIRCLE (line_to == 0), world-pinned.
func _slam() -> void:
	_casting = true
	var center: Vector2 = boss.global_position
	# Commit the body: hold position through the wind-up + a short recovery so it
	# doesn't stroll out of its own danger ring while the slam resolves.
	boss.action_root_until_ms = Time.get_ticks_msec() + int((slam_windup_s + SLAM_RECOVER_S) * 1000.0)
	# Filling telegraph (clock-wedge countdown) — players read WHEN it lands.
	boss.replicate_visual(&"rp_cast_telegraph", [center, slam_radius, slam_windup_s])
	await get_tree().create_timer(slam_windup_s).timeout
	if not is_instance_valid(boss) or boss.is_dead:
		_casting = false
		return
	# Impact: the ground burst + damage everyone still standing in the ring.
	boss.replicate_visual(&"rp_slam_impact", [center, slam_radius])
	var instance: Node = _instance()
	if instance != null:
		for peer_id: int in instance.players_by_peer_id:
			var player: Player = instance.players_by_peer_id[peer_id]
			if player != null and not player.is_dead \
					and center.distance_to(player.global_position) <= slam_radius:
				player.take_damage(slam_damage, boss)
	var interval: float = enraged_slam_interval_s if _enraged else slam_interval_s
	_next_slam_ms = Time.get_ticks_msec() + int(interval * 1000.0)
	_casting = false


## Phase 2: speed the body up, summon adds, and pull the next slam in so the shift
## reads as a real escalation.
func _enrage() -> void:
	_enraged = true
	boss.move_speed = int(boss.move_speed * enrage_speed_mult)
	_next_slam_ms = Time.get_ticks_msec() + int(enraged_slam_interval_s * 1000.0)
	_announce_enrage()
	_summon_adds.call_deferred() # spawn_dynamic toggles collision — defer out of the physics step


## Phase 2 is loud: a ground burst on the body + a danger banner & camera shake to
## everyone in the room, so the escalation reads instead of "suddenly more enemies
## and a faster boss" with no visible cause.
func _announce_enrage() -> void:
	var instance: Node = _instance()
	if instance == null:
		return
	boss.replicate_visual(&"rp_slam_impact", [boss.global_position, slam_radius * 0.8])
	for peer_id: int in instance.players_by_peer_id:
		WorldServer.curr.data_push.rpc_id(peer_id, &"boss.enrage", {"name": boss.display_name})


func _summon_adds() -> void:
	if not is_instance_valid(boss) or boss.container == null:
		return
	var container: ReplicatedPropsContainer = boss.container
	for i: int in add_count:
		var angle: float = TAU * float(i) / float(maxi(add_count, 1))
		var spot: Vector2 = boss.global_position + Vector2.RIGHT.rotated(angle) * add_spread_px
		var add: Node = container.spawn_dynamic(
			ReplicatedPropsContainer.SCENE_HOSTILE_NPC,
			container.to_local(spot),
			{"enemy_type_slug": add_enemy_slug}
		)
		if add != null:
			RoomNode.make_dungeon_mob(add, false)


## boss → ReplicatedPropsContainer → Map → ServerInstance.
func _instance() -> Node:
	if boss == null or boss.container == null:
		return null
	var map: Node = boss.container.get_parent()
	return map.get_parent() if map != null else null
