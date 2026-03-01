class_name AmbientLight
extends CanvasModulate


@export_group("Day Night Cycle")
@export var light_texture: GradientTexture1D
@export var enabled: bool:
	set(value):
		enabled = value
		set_process(value)


func _enter_tree() -> void:
	if multiplayer.is_server():
		queue_free()
	set_process(enabled)


func _process(_delta: float) -> void:
	var gradient_pos: float = Client.world_clock.get_day_progress()
	self.color = light_texture.gradient.sample(gradient_pos)
