class_name QuestInteraction
extends NPCInteraction
## NPC capability: offers/receives quests. Acts as the server-side "quest source"
## resolved via Map.get_quest_giver(giver_key) — the owning NPC's NPCResource filename
## slug is the giver key and its npc_name the giver name, so nothing is duplicated here.

@export var quests: Array[QuestResource]

## Owning NPC, stored on register() so the server can read the giver's display
## name off this source without keeping a second copy of it. Server-side only.
var _owner: NPC


func menu_entry(npc: Node) -> Dictionary:
	var owner: NPC = npc as NPC
	if owner == null:
		return {}
	# Having a QuestInteraction at all = a quest participant (offers and/or receives a
	# delivery), so the menu always shows; the server fills in offered + turn-inable.
	return {
		"label": _label_or("Quests"),
		"icon": _icon_or(""),
		"menu": &"quest",
		"arg": String(owner.giver_key()),
	}


func register(map: Map, npc: Node) -> void:
	_owner = npc as NPC
	if _owner != null:
		# register_keyed warns on key collisions. NOTE: unlike shops there is no
		# node-name fallback here — an INLINE NPCResource giver would key as ""
		# (quests can only reference givers by .tres file, so an inline giver
		# can't serve them anyway; all current givers are real .tres files).
		map.register_keyed(map.quest_givers, _owner.giver_key(), self, "quest giver")


## Quest-source field read by quest.list (duck-typed with QuestGiver.giver_name).
var giver_name: String:
	get:
		return _owner.display_name if _owner != null else ""
