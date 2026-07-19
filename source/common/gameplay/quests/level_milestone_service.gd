class_name LevelMilestoneService
## Fires a quest's unlock_message (a styled chat note "from" the giving NPC)
## at the moment the quest becomes ACCEPTABLE — i.e. when its LAST gate opens.
## Two gates exist (QuestResource.min_level + prerequisites_met), so there are
## two firing paths, partitioned so a single event never toasts twice:
##
## - on_levels_gained  — the level-up was the last gate (prereqs already met).
## - on_quest_turned_in — the prereq turn-in was the last gate (level already
##   met BEFORE this turn-in; level-ups granted BY the turn-in belong to the
##   on_levels_gained call that follows it in apply_turn_in).
##
## Empty unlock_message = no notification (the quest just appears silently at
## its giver). Cached on first use so we don't walk the quests registry every
## kill.

static var _by_min_level: Dictionary = {} # int -> Array[QuestResource]
static var _by_prereq: Dictionary = {} # prereq quest_id (int) -> Array[QuestResource]
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
	# Celebration broadcast: every call site that grants character levels funnels
	# through here, so this is the one spot where the whole instance learns about
	# the level-up (clients flare a VFX on the character — InstanceClient._on_level_up).
	var peer_id: int = int(player_res.current_peer_id)
	if peer_id > 0 and instance != null:
		ws.propagate_rpc(ws.data_push.bind(&"level.up", {"p": peer_id, "level": new_level}), instance.name)
	for level: int in range(old_level + 1, new_level + 1):
		for quest: QuestResource in _by_min_level.get(level, []):
			if quest == null or quest.unlock_message.is_empty():
				continue
			# Don't re-notify on a quest the player has already touched.
			if player_res.quests.has(int(quest.get_meta(&"id", 0))):
				continue
			# Chain gate still closed: the toast waits for the prereq turn-in
			# (on_quest_turned_in), so nothing says "come find me" early.
			if not quest.prerequisites_met(player_res):
				continue
			ws.chat_service.push_system_to_player(instance, player_res.player_id, quest.unlock_message)


## Called when a player turns in [param quest_id] (see QuestService.apply_turn_in).
## Fires unlock messages for quests that listed it as a prerequisite and are now
## fully available. [param old_level] is the player's level BEFORE the turn-in's
## XP: quests whose min_level sits above it are left to on_levels_gained (they
## unlock via the level, not the prereq), which is what makes the two paths
## mutually exclusive. An ANY-mode quest with several paths and an
## unlock_message may toast once per path completed until accepted — rare
## authoring shape, accepted.
static func on_quest_turned_in(player_res: PlayerResource, quest_id: int, old_level: int, instance: Node) -> void:
	if not _loaded:
		_load()
	var ws: WorldServer = WorldServer.curr
	if ws == null or ws.chat_service == null:
		return
	for quest: QuestResource in _by_prereq.get(quest_id, []):
		if quest == null or quest.unlock_message.is_empty():
			continue
		if player_res.quests.has(int(quest.get_meta(&"id", 0))):
			continue
		if quest.min_level > old_level:
			continue # the level gate was still closed — on_levels_gained's toast
		if not quest.prerequisites_met(player_res):
			continue # ALL mode with other prereqs still outstanding
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
		if quest == null:
			continue
		if quest.min_level > 0:
			var bucket: Array = _by_min_level.get_or_add(quest.min_level, [])
			bucket.append(quest)
		for prereq: QuestResource in quest.requires_quests:
			if prereq == null:
				continue
			var prereq_id: int = int(prereq.get_meta(&"id", 0))
			if prereq_id <= 0:
				continue
			var prereq_bucket: Array = _by_prereq.get_or_add(prereq_id, [])
			prereq_bucket.append(quest)
