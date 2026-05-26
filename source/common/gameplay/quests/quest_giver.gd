class_name QuestGiver
extends Area2D
## Clickable friendly NPC that offers and receives quests. Mirrors ShopInteractable /
## CraftingStation: lives below the HUD layer, works with mouse + touch, and only sends
## its giver_id to the server (which resolves the offered quests against the map).
##
## Setup: add this script to an Area2D with a CollisionShape2D over the NPC, give it a
## unique giver_id, assign the QuestResources it offers, and make it a direct child of
## the Map (like merchant / station nodes).

@export var giver_id: int = 0
@export var giver_name: String = "Quest Giver"
@export var quests: Array[QuestResource]


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
		ClientState.open_menu_requested.emit(&"quest", giver_id)
