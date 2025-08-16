extends Node
class_name HealthComponent


signal health_changed
signal max_health_changed


@export var hurtbox: Area2D
@export var progress_bar: ProgressBar

@export var state_synchronizer: StateSynchronizer

var health: float = 10.0:
	set(value):
		health = value
		progress_bar.value = value
		# Bonne méthode ?
		#state_synchronizer.mark_dirty_by_path(":health", value)
		health_changed.emit(value)
var max_health: float = 10.0:
	set(value):
		max_health = value
		progress_bar.max_value = value
		max_health_changed.emit(value)

var handle_projectile_callback: Callable = handle_projectile_server

class Property:
	var pid: int = 0
	var path: NodePath


func _init() -> void:
	pass


func _ready() -> void:
	if not multiplayer.is_server():
		handle_projectile_callback = handle_projectile_client
	hurtbox.area_entered.connect(_on_hurt_box_area_entered)



func apply_attack(attack: Attack) -> void:
	health -= attack.damage
	if OS.has_feature("client"):
		display_damage(attack)


func _on_hurt_box_area_entered(area: Area2D) -> void:
	if area is Projectile and area.attack and area.attack.source != owner:
		handle_projectile_callback.call(area)


func handle_projectile_client(projectile: Projectile) -> void:
	projectile.queue_free()

func handle_projectile_server(projectile: Projectile) -> void:
	apply_attack(projectile.attack)



func display_damage(attack: Attack) -> void:
		var label: Label = Label.new()
		label.global_position = owner.global_position
		label.text = str(attack.damage)
		label.top_level = true
		add_child(label)
		var tween: Tween = create_tween()
		tween.set_parallel()
		tween.tween_property(label, "modulate:a",0.3, 0.7)
		tween.tween_property(label, "scale", Vector2.ONE, 0.3)
		tween.tween_property(label, "scale", Vector2(0.4, 0.4), 1.0).set_delay(0.6)
		tween.chain().tween_callback(label.queue_free)
