class_name AmbientLight
extends CanvasModulate


@export_group("Day Night Cycle")
@export var enabled: bool = false
@export var light_texture: GradientTexture1D


func _enter_tree() -> void:
	if multiplayer.is_server():
		queue_free()


func _ready() -> void:
	pass


func _process(_delta: float) -> void:
	if not enabled:
		return

	var current_time: float = Client.world_clock.get_current_time()
	var gradient_pos: float = -cos(current_time * PI / 12.0) * 0.5 + 0.5

	self.color = light_texture.gradient.sample(gradient_pos)
