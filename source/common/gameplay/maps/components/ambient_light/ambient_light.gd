class_name AmbientLight
extends CanvasModulate

@export_group("Day Night Cycle")
@export var enabled: bool = false
@export var light_texture: GradientTexture1D

var _world_clock: WorldClockClient


func _ready() -> void:
	if multiplayer.is_server(): return
	_world_clock = Client.world_clock


func _process(_delta: float) -> void:
	if not enabled: return
	if multiplayer.is_server(): return

	var current_time: float = _world_clock.get_current_time()
	var gradient_pos: float = -cos(current_time * PI / 12.0) * 0.5 + 0.5
	
	self.color = light_texture.gradient.sample(gradient_pos)
