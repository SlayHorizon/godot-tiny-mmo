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

	# Verify the quest is actually offered by that giver in the player's map.
	var giver: QuestGiver = instance.instance_map.get_quest_giver(giver_id)
	if giver == null or not _giver_offers(giver, quest_id):
		return {"ok": false}

	var resource: PlayerResource = player.player_resource
	# Already active or turned in (v1 quests are one-time).
	if resource.quest_state(quest_id) != &"":
		return {"ok": false, "reason": "already"}

	resource.accept_quest(quest_id)
	return {"ok": true}


func _giver_offers(giver: QuestGiver, quest_id: int) -> bool:
	for quest: QuestResource in giver.quests:
		if quest and int(quest.get_meta(&"id", 0)) == quest_id:
			return true
	return false
