class_name DungeonExit
extends Area2D
## Clickable "leave the dungeon" station. Place it at the dungeon's entrance /
## spawn — where players also respawn on death, so it's right there when a run goes
## bad. Click → a confirm → return to town and drop from the run. Mirrors
## DungeonMaster. (Recall works as the universal escape too; this is the obvious,
## mob-proof one.)
##
## Setup: place as a direct child of the dungeon Map with a CollisionShape2D (the
## click target). Add a sprite child if you want it visible.


func _ready() -> void:
	if multiplayer.is_server():
		input_pickable = false
		return
	input_pickable = true
	input_event.connect(_on_input_event)


func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	var clicked: bool = (
		(event is InputEventMouseButton
			and event.button_index == MOUSE_BUTTON_LEFT
			and event.pressed)
		or (event is InputEventScreenTouch and event.pressed)
	)
	if clicked:
		ClientState.open_menu_requested.emit(&"dungeon_exit", 0)
