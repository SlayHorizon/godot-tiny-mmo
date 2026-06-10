class_name NPCInteraction
extends Resource
## Base class for ONE capability of an NPC (shop, quests, ...). An NPCResource
## holds an Array[NPCInteraction]; the NPC builds its greeting dialogue from them
## and registers their server-side capability. Subclasses override the two methods.
##
## These are pure data + behavior with no node needs, so they're Resources
## (configured inline in the NPC's .tres), not child nodes.
##
## The `npc` params are typed Node (not NPC) to avoid a circular class dependency
## (NPC's resource holds these); subclasses that need the NPC cast it (`npc as NPC`).

## Optional overrides for the dialogue button — empty means "use the subclass
## default" (so a ShopInteraction reads "Shop" / 🛒 without configuration).
@export var label_override: String = ""
@export var icon_override: String = ""


## Returns {"label", "icon", "menu": StringName, "arg"} describing this option's
## button + where selecting it routes (via ClientState.open_menu_requested).
## Return {} to offer nothing.
func menu_entry(_npc: Node) -> Dictionary:
	return {}


## Registers this capability into the map's server-side tables so the matching
## data-request handler can resolve it. No-op by default.
func register(_map: Map, _npc: Node) -> void:
	pass


func _label_or(default: String) -> String:
	return label_override if not label_override.is_empty() else default


func _icon_or(default: String) -> String:
	return icon_override if not icon_override.is_empty() else default
