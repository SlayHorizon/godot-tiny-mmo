extends DataRequestHandler


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if not player:
		return {"ok": false}

	var giver_id: int = int(args.get("giver", 0))
	var quest_id: int = int(args.get("id", 0))

	var giver: Object = instance.instance_map.get_quest_giver(giver_id)
	if giver == null:
		return {"ok": false}

	var quest: QuestResource = QuestResource.load_quest(quest_id)
	if quest == null:
		return {"ok": false}

	# Two valid scenarios for turn-in:
	#   1. Same giver offered + turns in (turn_in_giver_id == 0, default).
	#   2. Delivery: different giver, but quest.turn_in_giver_id == this giver.
	var valid_turn_in: bool = false
	if quest.turn_in_giver_id > 0:
		valid_turn_in = giver_id == quest.turn_in_giver_id
	else:
		valid_turn_in = _giver_offers(giver, quest_id)
	if not valid_turn_in:
		return {"ok": false, "reason": "wrong_giver"}

	var resource: PlayerResource = player.player_resource
	if resource.quest_state(quest_id) != &"active":
		return {"ok": false}
	if not QuestService.is_complete(resource, quest_id, resource.inventory):
		return {"ok": false, "reason": "incomplete"}

	# All validated — delegate the actual reward + push pipeline to the shared
	# QuestService method (same one auto_complete quests use).
	QuestService.apply_turn_in(resource, quest, peer_id, instance)

	return {"ok": true, "name": quest.quest_name}


func _giver_offers(giver: Object, quest_id: int) -> bool:
	for quest: QuestResource in giver.get(&"quests"):
		if quest and int(quest.get_meta(&"id", 0)) == quest_id:
			return true
	return false
