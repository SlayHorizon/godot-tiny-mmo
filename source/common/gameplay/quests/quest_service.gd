class_name QuestService
## Server-side quest logic shared by the kill/craft hooks and the quest handlers.
## Pure functions over a PlayerResource — no per-instance state.


## A player killed an enemy of [param enemy_type]: advance matching KILL objectives.
## Returns human-readable progress lines for client feedback.
static func on_kill(resource: PlayerResource, enemy_type: StringName) -> Array:
	return _advance_matching(resource, QuestObjective.Type.KILL, enemy_type)


## A player crafted [param item_id]: advance matching CRAFT objectives.
static func on_craft(resource: PlayerResource, item_id: int) -> Array:
	return _advance_matching(resource, QuestObjective.Type.CRAFT, item_id)


## A player opened the quest menu at [param giver_id]: advance matching VISIT
## objectives. VISIT objectives are single-fire (required_amount typically 1),
## so re-visiting after completion is a no-op.
static func on_visit(resource: PlayerResource, giver_id: int) -> Array:
	return _advance_matching(resource, QuestObjective.Type.VISIT, giver_id)


static func _advance_matching(resource: PlayerResource, objective_type: int, key: Variant) -> Array:
	var updates: Array = []
	for quest_id: int in resource.quests:
		if resource.quest_state(quest_id) != &"active":
			continue
		var quest: QuestResource = QuestResource.load_quest(quest_id)
		if quest == null:
			continue
		# Snapshot completion state so we can detect the moment a quest crosses
		# from incomplete -> ready and append a clear "✓ ready to turn in"
		# toast on top of the per-objective progress line.
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
			updates.append("✓ %s ready — return to the quest giver." % quest.quest_name)
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
