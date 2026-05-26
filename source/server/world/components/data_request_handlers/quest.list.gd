extends DataRequestHandler
## Returns quest views. With {"giver": id} -> the quests that giver offers (with the
## player's state on each). Without it -> the player's own quests (for a quest log).


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if not player:
		return {}

	var resource: PlayerResource = player.player_resource
	var inventory: Dictionary = resource.inventory

	var quest_ids: Array = []
	var giver_id: int = int(args.get("giver", 0))
	var giver_name: String = ""
	if giver_id > 0:
		var giver: QuestGiver = instance.instance_map.get_quest_giver(giver_id)
		if giver:
			giver_name = giver.giver_name
			for quest: QuestResource in giver.quests:
				if quest:
					quest_ids.append(int(quest.get_meta(&"id", 0)))
	else:
		quest_ids = resource.quests.keys()

	var out: Array = []
	for quest_id: int in quest_ids:
		out.append(_quest_view(resource, int(quest_id), inventory))
	return {"giver": giver_id, "giver_name": giver_name, "quests": out}


func _quest_view(resource: PlayerResource, quest_id: int, inventory: Dictionary) -> Dictionary:
	var quest: QuestResource = QuestResource.load_quest(quest_id)
	if quest == null:
		return {"id": quest_id, "name": "?", "objectives": []}

	var objectives: Array = []
	for i: int in quest.objectives.size():
		var objective: QuestObjective = quest.objectives[i]
		objectives.append({
			"desc": objective.describe(),
			"count": QuestService.objective_count(resource, quest_id, i, objective, inventory),
			"required": objective.required_amount,
		})

	return {
		"id": quest_id,
		"name": quest.quest_name,
		"description": quest.description,
		"state": String(resource.quest_state(quest_id)), # "" / "active" / "turned_in"
		"complete": QuestService.is_complete(resource, quest_id, inventory),
		"objectives": objectives,
		"reward_xp": quest.reward_xp,
		"reward_gold": quest.reward_gold,
	}
