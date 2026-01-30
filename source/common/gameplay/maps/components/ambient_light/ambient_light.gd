class_name AmbientLight
extends CanvasModulate


@export_group("Day Night Cycle")
@export var enabled: bool = false
@export var light_texture: GradientTexture1D


func _enter_tree() -> void:
	if multiplayer.is_server():
		queue_free()


func _process(delta: float) -> void:
	if not enabled: return
	var gradient_pos: float = Client.world_clock.get_day_progress()
	self.color = light_texture.gradient.sample(gradient_pos)
