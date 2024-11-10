#class_name WorldMain
extends Node


func _ready() -> void:
	Engine.set_physics_ticks_per_second(20) # 60 by default
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_title("World Server")
