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
## receive it). Tuning lives here as plain defaults for now — promote to a resource
## on SpawnMarker if bosses need per-fight knobs.

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
var add_enemy_slug: StringName = &"shadow_grunt"
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
	_next_slam_ms = Time.get_ticks_msec() + int(slam_interval_s * 1000.0)


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
	boss.replicate_visual(&"rp_lunge_telegraph", [center, slam_radius, slam_windup_s])
	await get_tree().create_timer(slam_windup_s).timeout
	if not is_instance_valid(boss) or boss.is_dead:
		_casting = false
		return
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
	_summon_adds.call_deferred() # spawn_dynamic toggles collision — defer out of the physics step


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
