class_name QuestInteraction
extends NPCInteraction
## NPC capability: offers/receives quests. Acts as the server-side "quest source"
## resolved via Map.get_quest_giver(npc_id) — duck-typed with the legacy
## QuestGiver node (both expose `quests` + `giver_name`). The owning NPC's npc_id
## is the giver id and its npc_name the giver name, so nothing is duplicated here.

@export var quests: Array[QuestResource]

## Owning NPC, stored on register() so the server can read the giver's display
## name off this source without keeping a second copy of it. Server-side only.
var _owner: NPC


func menu_entry(npc: Node) -> Dictionary:
	var owner: NPC = npc as NPC
	if owner == null:
		return {}
	if quests.is_empty() and owner.npc_id == 0:
		return {}
	return {
		"label": _label_or("Quests"),
		"icon": _icon_or(""),
		"menu": &"quest",
		"arg": owner.npc_id,
	}


func register(map: Map, npc: Node) -> void:
	_owner = npc as NPC
	if _owner != null:
		map.quest_givers[_owner.npc_id] = self


## Quest-source field read by quest.list (duck-typed with QuestGiver.giver_name).
var giver_name: String:
	get:
		return _owner.display_name if _owner != null else ""
