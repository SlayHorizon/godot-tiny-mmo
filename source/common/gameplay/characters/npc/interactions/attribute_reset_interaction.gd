class_name AttributeResetInteraction
extends NPCInteraction
## NPC capability: re-spec — refunds all spent attribute points for a gold fee so
## the player can rebuild a different way. Opens a confirm dialog; the reset itself
## is the server-authoritative attribute.reset handler, which reads COST here so
## the displayed price and the charged price can't drift.

## Gold fee for a respec. Single source of truth — the server handler reads it too.
const COST: int = 10


func menu_entry(_npc: Node) -> Dictionary:
	return {
		"label": _label_or("Respec attributes"),
		"icon": _icon_or(""),
		"menu": &"attribute_reset",
		"arg": COST,
	}
