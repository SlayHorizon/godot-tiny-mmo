class_name DuelMaster
extends Area2D
## Clickable NPC that queues players for a 1v1 spar. Mirrors QuestGiver: send
## only the master_id to the server, the server resolves the configured spawn
## points against the map.
##
## Setup: place as a direct child of a Map; give it a unique master_id; assign
## spawn_a / spawn_b to two Marker2D nodes inside the closed arena area; place
## the DuelMaster itself in the corridor (its own position is also the return
## point after the match ends).

@export var master_id: int = 0
@export var master_name: String = "Duel Master"
## Two spawn points inside the closed arena area. Designer places these Markers
## anywhere in the map; server teleports the first queued player to spawn_a and
## the second to spawn_b at match start.
@export var spawn_a: Marker2D
@export var spawn_b: Marker2D
## Optional Area2D enclosing the arena interior. If wired, a fighter who leaves
## the zone mid-match instantly loses (anti-exploit). Without it the match has
## no positional bounds — fine for an enclosed walled arena where you trust
## the geometry.
@export var fight_zone: Area2D


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
		ClientState.open_menu_requested.emit(&"sparring", master_id)
