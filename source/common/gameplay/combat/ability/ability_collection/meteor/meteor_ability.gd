class_name MeteorAbility
extends AbilityResource
## METEOR — the wand's T4 ultimate. Aim a direction: a danger circle telegraphs the
## impact point [member cast_range] px ahead, a comet screams down from the sky in the
## wind-up's last stretch, and the blast deals heavy AP damage to everything in the
## radius. Big, loud, and fully counterplayable — targets see the circle and can walk
## out (the wand's Battle Form moment).
##
## Direction-at-fixed-range targeting (mobile-friendly), not a free cursor. Reuses:
## CastTelegraph (the earthshatter danger marker), the centered MeleeArc (blast hitbox),
## the Starcaller comet + Fire Explosion sheets. Server owns the damage; every client
## renders the telegraph/comet/boom from the action echo.

## Blast damage = caster AP × this.
@export var ap_ratio: float = 2.0
@export var blast_radius: float = 70.0
## Impact lands this far ahead of the caster, along the aim.
@export var cast_range: float = 140.0
## Telegraph-to-impact delay (the counterplay window).
@export var windup_s: float = 1.3
## How long the comet visually falls (the wind-up's last stretch).
@export var fall_s: float = 0.35
@export var arc_scene: PackedScene = preload("res://source/common/gameplay/combat/melee_arc_centered.tscn")

const COMET: SpriteFrames = preload("res://source/common/gameplay/combat/vfx/star_comet.tres")
const BOOM: SpriteFrames = preload("res://source/common/gameplay/combat/vfx/fire_explosion.tres")


func use_ability(user: Entity, direction: Vector2) -> void:
	if user is not Character:
		return
	var dir: Vector2 = direction.normalized() if direction != Vector2.ZERO else Vector2.RIGHT
	var target: Vector2 = user.global_position + dir * cast_range
	if GameMode.is_client():
		_client_telegraph(user, target)
	if not GameMode.is_world_server():
		return
	(user as Character).get_tree().create_timer(windup_s).timeout.connect(
		_impact.bind(user as Character, target))


## The danger circle at the impact point, live for the whole wind-up; the comet fall
## is scheduled for the last stretch so it LANDS exactly when the damage fires.
func _client_telegraph(user: Entity, target: Vector2) -> void:
	var map: Node = user.get_parent()
	if map == null:
		return
	var tele: CastTelegraph = CastTelegraph.new()
	tele.radius = blast_radius
	tele.duration = windup_s
	map.add_child(tele)
	tele.global_position = target
	user.get_tree().create_timer(maxf(0.0, windup_s - fall_s)).timeout.connect(
		_client_fall.bind(map, target))


## The comet streaks down from above-right onto the point (the art flies down-left),
## then the explosion flashes at the moment of the server impact.
func _client_fall(map: Node, target: Vector2) -> void:
	if not is_instance_valid(map):
		return
	var comet: SpriteEffect = SpriteEffect.spawn(map, COMET, {
		"loop": true,
		"duration": fall_s + 0.1,  # frees itself right after landing
		"scale": Vector2(0.9, 0.9),
		"z_index": 3,
	})
	if comet != null:
		comet.global_position = target + Vector2(150.0, -230.0)
		var tween: Tween = comet.create_tween()
		tween.tween_property(comet, "global_position", target, fall_s)
		tween.tween_callback(_client_boom.bind(map, target))
	else:
		_client_boom(map, target)


func _client_boom(map: Node, target: Vector2) -> void:
	if not is_instance_valid(map):
		return
	var fx: SpriteEffect = SpriteEffect.spawn(map, BOOM, {
		"scale": Vector2(blast_radius * 2.2 / 128.0, blast_radius * 2.2 / 128.0),
		"z_index": 2,
	})
	if fx != null:
		fx.global_position = target


## Server blast at the telegraphed point. Guards against the caster dying/leaving
## mid-wind-up; the target POINT stays where it was aimed (no homing).
func _impact(caster: Character, target: Vector2) -> void:
	if not GameMode.is_world_server() or not is_instance_valid(caster) or caster.is_dead:
		return
	var map: Node = caster.get_parent()
	if map == null or arc_scene == null:
		return
	var arc: MeleeArc = arc_scene.instantiate()
	arc.source = caster
	var shape_node: CollisionShape2D = arc.get_node_or_null(^"CollisionShape2D") as CollisionShape2D
	if shape_node != null and shape_node.shape is CircleShape2D:
		var circle: CircleShape2D = shape_node.shape.duplicate()
		circle.radius = blast_radius
		shape_node.shape = circle
	arc.damage = caster.stats_component.get_stat(Stat.AP) * ap_ratio
	arc.damage_type = CombatHit.DAMAGE_MAGIC
	map.add_child(arc)
	arc.global_position = target


func extra_stat_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("%d%% AP blast" % int(round(ap_ratio * 100.0)))
	lines.append("%dpx radius" % int(blast_radius))
	lines.append("%ss wind-up" % fmt_num(windup_s))
	return lines
