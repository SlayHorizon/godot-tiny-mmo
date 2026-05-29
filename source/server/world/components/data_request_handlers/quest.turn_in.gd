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

	var giver: QuestGiver = instance.instance_map.get_quest_giver(giver_id)
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
	var inventory: Dictionary = resource.inventory
	if resource.quest_state(quest_id) != &"active":
		return {"ok": false}
	if not QuestService.is_complete(resource, quest_id, inventory):
		return {"ok": false, "reason": "incomplete"}

	# Consume COLLECT items (turning them in).
	for objective: QuestObjective in quest.objectives:
		if objective.type == QuestObjective.Type.COLLECT and objective.item:
			Inventory.remove_amount_by_id(inventory, int(objective.item.get_meta(&"id", 0)), objective.required_amount)

	# Consume the delivery item on turn-in (sealed letter, parcel) — it served
	# its narrative purpose and shouldn't linger in the bag.
	if quest.grant_on_accept:
		var grant_id: int = int(quest.grant_on_accept.get_meta(&"id", 0))
		if grant_id > 0:
			Inventory.remove_amount_by_id(inventory, grant_id, 1)

	# Grant rewards. Gold + items are pushed through the shared reward feedback channel
	# (gold is a currency item) so the client gets the same toasts + xp bar update.
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
	resource.set_quest_turned_in(quest_id)

	# Grant vanity title if the quest carries one. Adds to the unlocked list
	# and auto-equips only if the player has no title currently displayed.
	var quest_messages: Array = ["Quest complete: %s" % quest.quest_name]
	if not quest.grant_title.is_empty() and not resource.titles_unlocked.has(quest.grant_title):
		resource.titles_unlocked.append(quest.grant_title)
		if resource.display_title.is_empty():
			resource.display_title = quest.grant_title
		quest_messages.append("Title unlocked: %s" % quest.grant_title)

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

	# If this turn-in pushed us past a milestone, fire any per-level unlock
	# notifications styled as personal messages from the relevant NPCs.
	if int(progress.get("levels_gained", 0)) > 0:
		LevelMilestoneService.on_levels_gained(resource, level_before, int(progress.get("level", 1)), instance)

	return {"ok": true, "name": quest.quest_name}


func _giver_offers(giver: QuestGiver, quest_id: int) -> bool:
	for quest: QuestResource in giver.quests:
		if quest and int(quest.get_meta(&"id", 0)) == quest_id:
			return true
	return false
