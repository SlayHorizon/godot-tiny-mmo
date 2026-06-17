class_name DungeonMaster
extends Area2D
## LEGACY dungeon station. The NEW, meaningful way to offer a dungeon is a
## dungeon-keeper NPC with a DungeonInteraction (a real character) — see
## DungeonInteraction. This node is kept so existing entrance scenes keep working:
## it holds the dungeon and opens the lobby identified by its own NODE NAME (no
## manual id; the server resolves the station by name + range-checks its position).
##
## Setup: place as a direct child of a Map with a CollisionShape2D (the click
## target) and assign the [member dungeon]. Its position is the lobby anchor.

## The dungeon this station runs.
@export var dungeon: DungeonResource


func _ready() -> void:
	if dungeon == null:
		push_warning("DungeonMaster '%s' has no dungeon resource assigned." % name)
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
		ClientState.open_menu_requested.emit(&"dungeon", name) # station id = node name
