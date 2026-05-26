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


static func _advance_matching(resource: PlayerResource, objective_type: int, key: Variant) -> Array:
	var updates: Array = []
	for quest_id: int in resource.quests:
		if resource.quest_state(quest_id) != &"active":
			continue
		var quest: QuestResource = QuestResource.load_quest(quest_id)
		if quest == null:
			continue
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


## True when every objective of the quest is met.
static func is_complete(resource: PlayerResource, quest_id: int, inventory: Dictionary) -> bool:
	var quest: QuestResource = QuestResource.load_quest(quest_id)
	if quest == null:
		return false
	for i: int in quest.objectives.size():
		var objective: QuestObjective = quest.objectives[i]
		if objective_count(resource, quest_id, i, objective, inventory) < objective.required_amount:
			return false
	return true
