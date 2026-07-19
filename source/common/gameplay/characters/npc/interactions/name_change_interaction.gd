class_name NameChangeInteraction
extends NPCInteraction
## NPC capability: rename the character for a gold fee. Opens the name-change
## dialog; the rename itself is the server-authoritative name.change handler,
## which reads COST here so the displayed price and the charged price can't drift.

## Gold fee for a rename. Single source of truth — the server handler reads it too.
const COST: int = 20


func menu_entry(_npc: Node) -> Dictionary:
	return {
		"label": _label_or("Change name"),
		"icon": _icon_or(""),
		"menu": &"name_change",
		"arg": COST,
	}
