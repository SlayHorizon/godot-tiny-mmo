class_name ShopInteractable
extends Area2D
## World-space click/tap target that opens a shop. Lives below the HUD layer, so it
## never fights the shop UI for z-order. Works with both mouse and touch.
##
## Setup in the editor: add this script to an Area2D, give it a CollisionShape2D
## child over the merchant, and assign a ShopResource. Only its registry id is sent
## to the server (lightweight), so the shop must be generated as the "shops" content
## type first (see ShopResource).

@export var shop: ShopResource


func _ready() -> void:
	if multiplayer.is_server():
		# The server keeps the node but never handles input.
		input_pickable = false
		return
	if shop:
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
		input_event.disconnect(_on_input_event)
		get_tree().create_timer(2.0).timeout.connect(input_event.connect.bind(_on_input_event))
		ClientState.open_menu_requested.emit(&"shop", int(shop.get_meta(&"id", 0)))
