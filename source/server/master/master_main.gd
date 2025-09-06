extends Node


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_title("Master Server")
