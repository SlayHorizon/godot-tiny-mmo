class_name RainOfArrowsAbility
extends MeteorAbility
## RAIN OF ARROWS — the bow's zone-denial cast (the one bow ability that isn't a shot
## override, since it's point-targeted): aim → danger circle → a volley crashes down
## (AD-scaled AoE) — and the arrows STICK in the ground, leaving a slow zone behind.
## "Don't stand here." Reuses the Meteor telegraph/impact skeleton; swaps the comet
## for falling arrow sprites and adds a PLANTED SpellField for the lingering slow.

## The lingering slow zone the stuck arrows leave at the impact point.
@export var field_duration_s: float = 3.0
@export var field_slow: float = 18.0
@export var field_slow_duration_s: float = 1.2
@export var field_tick_s: float = 0.5
## Falling/stuck arrow visuals per cast.
@export var arrow_count: int = 7

const ARROW_TEX: Texture2D = preload("res://assets/sprites/items/weapons/wood/wood.png")
const ARROW_REGION: Rect2 = Rect2(32, 0, 16, 16)


## The volley: the arrows streak down and land DRAWING THE ZONE — a ring around the
## circle's edge plus one dead-centre — then STAY stuck for the slow zone's life before
## fading. Deterministic layout (no randomness), so every client sees the same volley.
func _client_fall(map: Node, target: Vector2) -> void:
	if not is_instance_valid(map):
		return
	var ring_count: int = maxi(2, arrow_count - 1)
	for i: int in arrow_count:
		# i == 0 lands centre; the rest space evenly around the ring.
		var land: Vector2 = target
		if i > 0:
			var ang: float = TAU * float(i - 1) / float(ring_count)
			land = target + Vector2.from_angle(ang) * blast_radius * 0.8
		var arrow: Sprite2D = Sprite2D.new()
		arrow.texture = ARROW_TEX
		arrow.region_enabled = true
		arrow.region_rect = ARROW_REGION
		arrow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		arrow.rotation = PI / 2.0  # nose to the ground (empirical: -PI/2 pointed up)
		arrow.z_index = 2
		map.add_child(arrow)
		arrow.global_position = land + Vector2(0.0, -170.0)
		var tween: Tween = arrow.create_tween()
		tween.tween_interval(fall_s * 0.6 * float(i) / float(arrow_count))  # staggered volley
		tween.tween_property(arrow, "global_position", land, fall_s * 0.5)
		# stuck: hold through the slow zone, then fade out
		tween.tween_interval(field_duration_s)
		tween.tween_property(arrow, "modulate:a", 0.0, 0.4)
		tween.tween_callback(arrow.queue_free)


## No explosion — the "boom" is the zone marker: the danger circle stays for the slow
## field's life so everyone reads the denied ground.
func _client_boom(map: Node, target: Vector2) -> void:
	if not is_instance_valid(map):
		return
	var zone: CastTelegraph = CastTelegraph.new()
	zone.radius = blast_radius
	zone.duration = field_duration_s
	map.add_child(zone)
	zone.global_position = target


## AD-scaled impact (the bow is an AD class, unlike the Meteor's AP) + plant the slow field.
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
	arc.damage = caster.stats_component.get_stat(Stat.AD) * ap_ratio
	map.add_child(arc)
	arc.global_position = target
	# The stuck arrows' slow zone, planted at the point (not riding the archer).
	var field: SpellField = SpellField.new()
	field.caster = caster
	field.arc_scene = arc_scene
	field.radius = blast_radius
	field.slow_amount = field_slow
	field.slow_duration_s = field_slow_duration_s
	field.tick_interval = field_tick_s
	field.duration = field_duration_s
	field.anchored = true
	field.anchor = target
	caster.add_child(field)


func extra_stat_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("%d%% AD volley" % int(round(ap_ratio * 100.0)))
	lines.append("%dpx zone" % int(blast_radius))
	lines.append("-%s move speed for %ss after" % [fmt_num(field_slow), fmt_num(field_duration_s)])
	return lines
