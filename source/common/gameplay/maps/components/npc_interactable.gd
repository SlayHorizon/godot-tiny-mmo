class_name NPCInteractable
extends QuestGiver
## A friendly NPC that offers SEVERAL actions from ONE node — instead of needing
## a separate Area2D per function (one for the shop, one for quests). On click it
## opens a small choice menu ("What can I do for you?") that routes to the
## EXISTING shop/quest menus; those menus and their server handlers are untouched.
##
## Extends QuestGiver on purpose: the server resolves a giver's quests via
## Map.get_quest_giver(giver_id), which only finds QuestGiver nodes (map.gd). A
## dedicated branch in map.gd also registers this node's shop into the map's shop
## table (shop.open authorizes against it).
##
## Setup (direct child of the Map, like other interactables):
##   • CollisionShape2D over the sprite (the click target)
##   • giver_name  → shown as the menu title (e.g. "Mira")
##   • shop        → a ShopResource, for a shopkeeper (optional)
##   • giver_id + quests → for a quest giver (optional)
##   • Add an InteractableMarker child with kind = DIALOG for the floating glyph.
## Any combination works — set just a shop, just quests, or both.

## The shop this NPC sells (optional; leave null for a quest-only NPC). Only its
## registry id reaches the client — the catalog renders from the local resource.
@export var shop: ShopResource


func _ready() -> void:
	# Intentionally does NOT call super(): QuestGiver._ready wires the click
	# straight to the quest menu, but we want it to open the choice menu instead.
	if multiplayer.is_server():
		# Server keeps the node (for quest/shop resolution) but never takes input.
		input_pickable = false
		return
	input_pickable = true
	input_event.connect(_on_npc_clicked)


func _on_npc_clicked(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	var clicked: bool = (
		(event is InputEventMouseButton
			and event.button_index == MOUSE_BUTTON_LEFT
			and event.pressed)
		or (event is InputEventScreenTouch and event.pressed)
	)
	if not clicked:
		return
	# Describe the actions this NPC offers; the menu builds a button per key.
	var actions: Dictionary = {"name": giver_name}
	if shop:
		actions["shop_id"] = int(shop.get_meta(&"id", 0))
	if giver_id != 0 or not quests.is_empty():
		actions["quest_giver_id"] = giver_id
	ClientState.open_menu_requested.emit(&"npc", actions)
