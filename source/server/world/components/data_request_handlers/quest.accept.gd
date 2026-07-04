extends DataRequestHandler


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if not player:
		return {"ok": false}

	var giver_key: StringName = StringName(str(args.get("giver", "")))
	var quest_id: int = int(args.get("id", 0))

	# Verify the quest is actually offered by that giver in the player's map.
	var giver: Object = instance.instance_map.get_quest_giver(giver_key)
	if giver == null or not _giver_offers(giver, quest_id):
		return {"ok": false}

	var resource: PlayerResource = player.player_resource
	# Already active or turned in (v1 quests are one-time).
	if resource.quest_state(quest_id) != &"":
		return {"ok": false, "reason": "already"}

	# FAIL CLOSED on a registry miss: a quest the registry can't resolve can
	# never progress or turn in (on_kill / load_quest skip null), so accepting
	# it just strands a dead entry in the player's log. Null here = the quests
	# index is stale in THIS process — Generate ran but the server wasn't
	# restarted (ContentRegistryHub loads indexes once, at static init).
	var quest: QuestResource = QuestResource.load_quest(quest_id)
	if quest == null:
		ServerLog.warn("quest.accept: id %d offered by '%s' but missing from the quests registry — Generate + RESTART the server." % [quest_id, giver_key])
		return {"ok": false, "reason": "unknown"}

	# Level gate: if the quest sets min_level, the player has to be at least
	# that high. Optional side quests use this for sparring/guild/basing intros.
	if quest.min_level > 0 and resource.level < quest.min_level:
		return {"ok": false, "reason": "level"}

	# Prerequisite gate (quest chains + the wardstone-flag seam). The giver list
	# shows unmet quests as locked rows with no Accept, but enforce here too so
	# a stale menu can't accept early.
	if not quest.prerequisites_met(resource):
		return {"ok": false, "reason": "prereq"}

	resource.accept_quest(quest_id)

	# Delivery quests grant a parcel/letter on accept (consumed at turn-in).
	if quest.grant_on_accept:
		var item_id: int = int(quest.grant_on_accept.get_meta(&"id", 0))
		if item_id > 0:
			Inventory.add_item(resource.inventory, item_id, 1)

	return {"ok": true}


func _giver_offers(giver: Object, quest_id: int) -> bool:
	for quest: QuestResource in giver.get(&"quests"):
		if quest and int(quest.get_meta(&"id", 0)) == quest_id:
			return true
	return false
