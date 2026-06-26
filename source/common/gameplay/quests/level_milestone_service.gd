class_name LevelMilestoneService
## On level-up, fire styled chat messages for any quest whose min_level matches
## the player's new level. Quests author the message themselves
## (QuestResource.unlock_message) — usually as a personal note from the giving
## NPC, e.g. "[Duel Master] I've heard you've been honing your blade. Find me
## at the arena." Empty unlock_message = no notification (the quest just
## becomes available silently on the giver's offer list).
##
## Cached on first use so we don't walk the whole quests registry every kill.

static var _by_min_level: Dictionary = {} # int -> Array[QuestResource]
static var _loaded: bool


## Called whenever a player's level changed. Walks the open range (old, new]
## so multi-level pops still fire each milestone in order.
static func on_levels_gained(player_res: PlayerResource, old_level: int, new_level: int, instance: Node) -> void:
	if not _loaded:
		_load()
	if new_level <= old_level:
		return
	var ws: WorldServer = WorldServer.curr
	if ws == null or ws.chat_service == null:
		return
	for level: int in range(old_level + 1, new_level + 1):
		for quest: QuestResource in _by_min_level.get(level, []):
			if quest == null or quest.unlock_message.is_empty():
				continue
			# Don't re-notify on a quest the player has already touched.
			if player_res.quests.has(int(quest.get_meta(&"id", 0))):
				continue
			ws.chat_service.push_system_to_player(instance, player_res.player_id, quest.unlock_message)


# --- internals ---

static func _load() -> void:
	_loaded = true
	var registry: ContentRegistry = ContentRegistryHub.registry_of(&"quests")
	if registry == null:
		return
	# ContentRegistry doesn't expose iteration; reach into _id_to_path.
	for id: int in registry._id_to_path.keys():
		var quest: QuestResource = ContentRegistryHub.load_by_id(&"quests", id) as QuestResource
		if quest == null or quest.min_level <= 0:
			continue
		var bucket: Array = _by_min_level.get_or_add(quest.min_level, [])
		bucket.append(quest)
