class_name DungeonInteraction
extends NPCInteraction
## NPC capability: opens the dungeon manager for [member dungeon]. The NPC IS the
## station — the server resolves it by NODE NAME (no manual id), reads this
## interaction's dungeon, and range-checks against the NPC's position. So a
## dungeon-keeper NPC (a real character) is the meaningful access point.

@export var dungeon: DungeonResource


func menu_entry(npc: Node) -> Dictionary:
	if dungeon == null:
		return {}
	return {
		"label": _label_or("Enter dungeon"),
		"icon": _icon_or(""),
		"menu": &"dungeon",
		"arg": String(npc.name), # the station id is the node name (auto, no manual id)
	}
