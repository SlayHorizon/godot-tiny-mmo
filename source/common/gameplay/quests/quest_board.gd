class_name QuestBoard
extends Area2D
## Clickable town board that posts the player's 3 daily quests. Mirrors
## QuestGiver: an Area2D + sprite, clicking opens the daily_board menu.
##
## Setup: place as a direct child of a Map; add a CollisionShape2D over the
## visible board. Only one is needed per map (player state is per-player, not
## per-board) — though multiple are fine if you want them in several towns.


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
		ClientState.open_menu_requested.emit(&"daily_board", 0)
