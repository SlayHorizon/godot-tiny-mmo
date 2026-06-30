class_name SpellField
extends Node2D
## A short-lived AoE field that rides the caster: every [member tick_interval] it spawns
## a centered MeleeArc (damage + slow) at the caster's CURRENT position for [member
## duration] seconds, then frees. Fire-and-forget — it does NOT root the caster (unlike a
## channel), so a battlemage keeps fighting while it crackles. Server-only (the VFX is
## broadcast separately by the ability). Used by NovaAbility's lingering mode (Static Field).

var caster: Character
var arc_scene: PackedScene
var radius: float = 80.0
var damage: float = 0.0
var damage_type: StringName = CombatHit.DAMAGE_MAGIC
var slow_amount: float = 0.0
var slow_duration_s: float = 0.0
var heal_per_hit: float = 0.0
var mana_per_hit: float = 0.0
var tick_interval: float = 0.5
var duration: float = 2.5

var _elapsed: float = 0.0
var _next_tick: float = 0.0


func _ready() -> void:
	_tick()  # strike immediately on cast


func _process(delta: float) -> void:
	_elapsed += delta
	_next_tick -= delta
	if _next_tick <= 0.0:
		_next_tick = tick_interval
		_tick()
	if _elapsed >= duration:
		queue_free()


func _tick() -> void:
	if not is_instance_valid(caster) or caster.is_dead or arc_scene == null or caster.get_parent() == null:
		queue_free()
		return
	var arc: MeleeArc = arc_scene.instantiate()
	arc.source = caster
	var shape_node: CollisionShape2D = arc.get_node_or_null(^"CollisionShape2D") as CollisionShape2D
	if shape_node != null and shape_node.shape is CircleShape2D:
		var circle: CircleShape2D = shape_node.shape.duplicate()
		circle.radius = radius
		shape_node.shape = circle
	arc.damage = damage
	arc.damage_type = damage_type
	arc.slow_amount = slow_amount
	arc.slow_duration_s = slow_duration_s
	arc.heal_per_hit = heal_per_hit
	arc.mana_per_hit = mana_per_hit
	caster.get_parent().add_child(arc)
	arc.global_position = caster.global_position
