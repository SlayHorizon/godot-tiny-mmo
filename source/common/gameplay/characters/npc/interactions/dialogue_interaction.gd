class_name DialogueInteraction
extends NPCInteraction
## NPC capability: flavor / lore talk. Selecting it plays `lines` one page at a
## time in the dialogue box (no branching — dead simple), then returns to the
## options. The Undertale "talk to the character" beyond the shop/quest options.

## Each element is one page of dialogue, shown one at a time (click to advance).
@export var lines: Array[String]


func menu_entry(_npc: Node) -> Dictionary:
	if lines.is_empty():
		return {}
	return {
		"label": _label_or("Talk"),
		"icon": _icon_or(""),
		"lines": lines,
	}
