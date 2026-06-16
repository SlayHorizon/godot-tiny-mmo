class_name DungeonMaster
extends Area2D
## Clickable dungeon LOBBY station — place it in the entrance map. Click → opens
## the dungeon lobby menu; players queue up, then Start sends the WHOLE group into
## a fresh PRIVATE instance of [member dungeon_name] (DungeonService.start_run).
## Solo is allowed (a Solo button, or pressing Start alone). Mirrors DuelMaster.
##
## Setup: place as a direct child of a Map; give it a unique positive master_id
## and a CollisionShape2D (the click target). Its own position is the lobby anchor
## (players must be within range to queue, and it's where the dungeon's "in front
## of the entrance" feel comes from).

@export var master_id: int = 0
## Shown as the lobby title.
@export var master_name: String = "Dungeon"
## instance_name of the dungeon InstanceResource this station runs (e.g. "Dungeon").
@export var dungeon_name: String = "Dungeon"
## Max party size for a single run.
@export var party_size: int = 4


func _ready() -> void:
	if master_id <= 0:
		push_warning("DungeonMaster '%s' has master_id=%d — set a unique positive id." % [name, master_id])
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
		ClientState.open_menu_requested.emit(&"dungeon", master_id)
