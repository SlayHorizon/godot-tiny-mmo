extends Camera3D


func _ready() -> void:
	var tween := create_tween()
	tween.set_loops()
	tween.tween_property(self, "rotation_degrees:y", 360.0, 100.0).from(0.0)
