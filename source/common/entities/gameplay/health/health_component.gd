extends Node
class_name HealthComponent


signal health_changed
signal max_health_changed


@export var hurtbox: Area2D
@export var progress_bar: ProgressBar

var health: float = 10.0:
	set(value):
		health = value
		progress_bar.value = value
		health_changed.emit(value)
var max_health: float = 10.0:
	set(value):
		max_health = value
		progress_bar.max_value = value
		max_health_changed.emit(value)


#func _init(_health: float, _max_health: float) -> void:
	#health = _health
	#max_health = _max_health


func _ready() -> void:
	hurtbox.area_entered.connect(_on_hurt_box_area_entered)
	progress_bar.min_value = 0.0
	progress_bar.max_value = max_health
	progress_bar.value = health


func apply_attack(attack: Attack) -> void:
	health -= attack.damage
	if OS.has_feature("client"):
		display_damage(attack)


func _on_hurt_box_area_entered(area: Area2D) -> void:
	if area is Projectile and area.attack and area.attack.source != owner:
		apply_attack(area.attack)
		area.queue_free()


func display_damage(attack: Attack) -> void:
		var label := Label.new()
		label.global_position = owner.global_position
		label.text = str(attack.damage)
		label.top_level = true
		add_child(label)
		var tween := create_tween()
		tween.set_parallel()
		tween.tween_property(label, "modulate:a",0.3, 0.7)
		tween.tween_property(label, "scale", Vector2.ONE, 0.3)
		tween.tween_property(label, "scale", Vector2(0.4, 0.4), 1.0).set_delay(0.6)
		tween.chain().tween_callback(label.queue_free)
