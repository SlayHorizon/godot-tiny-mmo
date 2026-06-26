class_name QuestService
## Server-side quest logic shared by the kill/craft hooks and the quest handlers.
## Pure functions over a PlayerResource — no per-instance state.


## A player killed an enemy of [param enemy_type]: advance matching KILL objectives.
## Returns human-readable progress lines for client feedback. peer_id + instance
## are needed for the auto_complete path (turn-in pushes / milestones) and can be
## omitted in tests or contexts that don't care.
static func on_kill(
	resource: PlayerResource, enemy_type: StringName,
	peer_id: int = 0, instance: Node = null
) -> Array:
	return _advance_matching(resource, QuestObjective.Type.KILL, enemy_type, peer_id, instance)


## A player crafted [param item_id]: advance matching CRAFT objectives.
static func on_craft(
	resource: PlayerResource, item_id: int,
	peer_id: int = 0, instance: Node = null
) -> Array:
	return _advance_matching(resource, QuestObjective.Type.CRAFT, item_id, peer_id, instance)


## A player opened the quest menu at [param giver_id]: advance matching VISIT
## objectives. VISIT objectives are single-fire (required_amount typically 1),
## so re-visiting after completion is a no-op.
static func on_visit(
	resource: PlayerResource, giver_id: int,
	peer_id: int = 0, instance: Node = null
) -> Array:
	return _advance_matching(resource, QuestObjective.Type.VISIT, giver_id, peer_id, instance)


static func _advance_matching(
	resource: PlayerResource, objective_type: int, key: Variant,
	peer_id: int = 0, instance: Node = null
) -> Array:
	var updates: Array = []
	# Auto-complete fires can't happen mid-iteration of resource.quests because
	# apply_turn_in mutates it (set_quest_turned_in). Defer the fires to after
	# the iteration to keep the dict stable.
	var pending_auto_complete: Array[QuestResource] = []
	for quest_id: int in resource.quests:
		if resource.quest_state(quest_id) != &"active":
			continue
		var quest: QuestResource = QuestResource.load_quest(quest_id)
		if quest == null:
			continue
		# Snapshot completion state so we can detect the moment a quest crosses
		# from incomplete -> ready and append the right end-of-quest toast.
		var was_complete: bool = is_complete(resource, quest_id, resource.inventory)
		for i: int in quest.objectives.size():
			var objective: QuestObjective = quest.objectives[i]
			if objective.type != objective_type or objective.target_key() != key:
				continue
			if resource.quest_progress(quest_id, i) >= objective.required_amount:
				continue # already done
			resource.advance_quest(quest_id, i, 1)
			updates.append("%s: %s (%d/%d)" % [
				quest.quest_name, objective.describe(),
				resource.quest_progress(quest_id, i), objective.required_amount
			])
		if not was_complete and is_complete(resource, quest_id, resource.inventory):
			if quest.auto_complete:
				# apply_turn_in pushes its own quest.update toast — don't append
				# the "ready — return" line that'd confuse the player.
				pending_auto_complete.append(quest)
			else:
				# Latch so notify_passive_ready (the COLLECT path) doesn't re-toast this.
				resource.set_quest_ready_notified(quest_id, true)
				updates.append("✓ %s ready to turn in. Return to the quest giver." % quest.quest_name)
	for quest: QuestResource in pending_auto_complete:
		apply_turn_in(resource, quest, peer_id, instance)
	return updates


## Current progress for one objective: stored counter for KILL/CRAFT, live inventory
## count for COLLECT (capped at required for display sanity).
static func objective_count(
	resource: PlayerResource, quest_id: int, objective_index: int,
	objective: QuestObjective, inventory: Dictionary
) -> int:
	if objective.type == QuestObjective.Type.COLLECT:
		var item_id: int = int(objective.item.get_meta(&"id", 0)) if objective.item else 0
		return mini(Inventory.count(inventory, item_id), objective.required_amount)
	return mini(resource.quest_progress(quest_id, objective_index), objective.required_amount)


## Applies a turn-in: consumes COLLECT items + the delivery item, grants XP /
## gold / item rewards, marks the quest turned_in, unlocks any title, pushes
## the combat.reward + quest.update feedback, and fires milestone unlocks.
## Shared between the manual turn-in handler and the auto_complete path that
## fires from inside _advance_matching the moment a self-completing quest
## crosses its bar.
static func apply_turn_in(
	resource: PlayerResource,
	quest: QuestResource,
	peer_id: int,
	instance: Node
) -> void:
	var inventory: Dictionary = resource.inventory

	# Consume COLLECT items + grant_on_accept (delivery item served its narrative).
	for objective: QuestObjective in quest.objectives:
		if objective.type == QuestObjective.Type.COLLECT and objective.item:
			Inventory.remove_amount_by_id(
				inventory, int(objective.item.get_meta(&"id", 0)), objective.required_amount
			)
	if quest.grant_on_accept:
		var grant_id: int = int(quest.grant_on_accept.get_meta(&"id", 0))
		if grant_id > 0:
			Inventory.remove_amount_by_id(inventory, grant_id, 1)

	# Pay rewards. Loot list is shared with the combat.reward push so the client
	# gets the same toasts + XP-bar handling a kill gives.
	var loot: Array = []
	if quest.reward_gold > 0:
		Inventory.add_item(inventory, Economy.gold_id(), quest.reward_gold)
		loot.append({"id": Economy.gold_id(), "amount": quest.reward_gold, "name": "Gold"})
	for reward: QuestReward in quest.reward_items:
		if reward and reward.item:
			var reward_id: int = int(reward.item.get_meta(&"id", 0))
			Inventory.add_item(inventory, reward_id, reward.amount)
			loot.append({"id": reward_id, "amount": reward.amount, "name": str(reward.item.item_name)})

	var level_before: int = resource.level
	var progress: Dictionary = resource.add_experience(quest.reward_xp)
	var quest_id: int = int(quest.get_meta(&"id", 0))
	resource.set_quest_turned_in(quest_id)

	# Vanity title grant — auto-equips only if no title currently displayed.
	var quest_messages: Array = ["Quest complete: %s" % quest.quest_name]
	if not quest.grant_title.is_empty() and not resource.titles_unlocked.has(quest.grant_title):
		resource.titles_unlocked.append(quest.grant_title)
		if resource.display_title.is_empty():
			resource.display_title = quest.grant_title
		quest_messages.append("Title unlocked: %s" % quest.grant_title)

	if peer_id > 0:
		WorldServer.curr.data_push.rpc_id(peer_id, &"combat.reward", {
			"xp": quest.reward_xp,
			"level": int(progress.get("level", 1)),
			"levels_gained": int(progress.get("levels_gained", 0)),
			"points_gained": int(progress.get("points_gained", 0)),
			"experience": resource.experience,
			"xp_to_next": resource.level_xp_to_next(),
			"loot": loot,
		})
		WorldServer.curr.data_push.rpc_id(peer_id, &"quest.update", {"messages": quest_messages})

	if int(progress.get("levels_gained", 0)) > 0 and instance != null:
		LevelMilestoneService.on_levels_gained(
			resource, level_before, int(progress.get("level", 1)), instance
		)


## True when the quest's completion rule is satisfied. ALL = every objective met
## (classic AND); ANY = at least one objective met (for "pick a path" quests).
static func is_complete(resource: PlayerResource, quest_id: int, inventory: Dictionary) -> bool:
	var quest: QuestResource = QuestResource.load_quest(quest_id)
	if quest == null:
		return false
	if quest.objectives.is_empty():
		# No-objective quest (e.g. visit-then-turn-in) — complete on accept.
		return true
	var any_met: bool = false
	for i: int in quest.objectives.size():
		var objective: QuestObjective = quest.objectives[i]
		var met: bool = objective_count(resource, quest_id, i, objective, inventory) >= objective.required_amount
		if met:
			any_met = true
		elif quest.completion == QuestResource.Completion.ALL:
			return false
	return any_met


## Pushes the "ready to turn in" toast for any active quest that became complete
## via a passive path (COLLECT items now in the bag) that fires no advance event.
## Latches per quest so a tracker refresh doesn't re-toast, and clears the latch
## if the quest drops back below complete (items sold/lost). KILL/CRAFT/VISIT
## completions are already latched by _advance_matching, so they're skipped here.
static func notify_passive_ready(resource: PlayerResource, peer_id: int) -> void:
	if peer_id <= 0:
		return
	for quest_id: int in resource.quests:
		if resource.quest_state(quest_id) != &"active":
			continue
		var quest: QuestResource = QuestResource.load_quest(quest_id)
		if quest == null or quest.auto_complete:
			continue
		var complete: bool = is_complete(resource, quest_id, resource.inventory)
		var notified: bool = resource.quest_ready_notified(quest_id)
		if complete and not notified:
			resource.set_quest_ready_notified(quest_id, true)
			WorldServer.curr.data_push.rpc_id(peer_id, &"quest.update", {
				"messages": ["✓ %s ready to turn in. Return to the quest giver." % quest.quest_name]
			})
		elif not complete and notified:
			resource.set_quest_ready_notified(quest_id, false)
