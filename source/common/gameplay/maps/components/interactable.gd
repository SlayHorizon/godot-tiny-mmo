class_name Interactable
extends Area2D
## A clickable map station. On a left-click / tap it opens a client menu —
## open_menu_requested(menu_name, menu_arg). Centralizes the input-pickable +
## click-detection boilerplate that every station used to copy.
##
## Two ways to use it:
##  • SIMPLE station — just this node, configured in the inspector (menu_name +
##    menu_arg). No script needed (DungeonExit, a quest board, …).
##  • STATEFUL station — a node with its own server-side data (DungeonMaster,
##    DuelMaster) EXTENDS this, sets menu_name/menu_arg in _ready, calls
##    super._ready(), and keeps its fields. The click is inherited.
##
## The server never clicks, so it just disables input; the client wires the handler.

## The client menu to open on click. Empty = inert (a non-clickable decoration).
@export var menu_name: StringName = &""
## Argument passed to that menu's open() — e.g. a station id (master_id), or 0 when
## the menu takes none.
@export var menu_arg: int = 0


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
	if clicked and menu_name != &"":
		ClientState.open_menu_requested.emit(menu_name, menu_arg)
