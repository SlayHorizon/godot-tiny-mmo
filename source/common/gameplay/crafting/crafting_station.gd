class_name CraftingStation
extends Area2D
## World-space click/tap target that opens a crafting station (workbench, anvil, ...).
## Mirrors ShopInteractable: lives below the HUD layer, works with mouse and touch, and
## only sends the station's registry id to the server (which validates it against the map).
##
## Setup: add this script to an Area2D, give it a CollisionShape2D over the station, and
## assign a CraftingStationResource (generated as the "crafting_stations" content type).
## Place it as a direct child of the Map (like merchant / warper nodes).

@export var station: CraftingStationResource


func _ready() -> void:
	if multiplayer.is_server():
		input_pickable = false
		return
	if station:
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
		ClientState.open_menu_requested.emit(&"crafting", int(station.get_meta(&"id", 0)))
