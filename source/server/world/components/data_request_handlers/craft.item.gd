extends DataRequestHandler


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var station_id: int = int(args.get("station", 0))
	var recipe_index: int = int(args.get("recipe", -1))

	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if not player:
		return {"ok": false}

	# Resolve the station from the player's map (authoritative + verifies they're at it).
	var station: CraftingStationResource = instance.instance_map.get_crafting_station(station_id)
	if station == null:
		return {"ok": false}
	if recipe_index < 0 or recipe_index >= station.recipes.size():
		return {"ok": false}
	var recipe: CraftingRecipe = station.recipes[recipe_index]
	if recipe == null or recipe.output_item == null:
		return {"ok": false}

	var resource: PlayerResource = player.player_resource
	var inventory: Dictionary = resource.inventory

	# Crafting-profession level gate.
	var level: int = int((resource.skills.get(station.profession, {}) as Dictionary).get("level", 1))
	if level < recipe.required_level:
		return {"ok": false, "reason": "level", "required_level": recipe.required_level}

	# Verify every ingredient is available before consuming any (atomic craft).
	for ingredient: CraftIngredient in recipe.ingredients:
		if ingredient == null or ingredient.item == null:
			continue
		var ing_id: int = int(ingredient.item.get_meta(&"id", 0))
		if Inventory.count(inventory, ing_id) < ingredient.amount:
			return {"ok": false, "reason": "ingredients"}

	# Consume ingredients.
	for ingredient: CraftIngredient in recipe.ingredients:
		if ingredient == null or ingredient.item == null:
			continue
		var ing_id: int = int(ingredient.item.get_meta(&"id", 0))
		Inventory.remove_amount_by_id(inventory, ing_id, ingredient.amount)

	# Grant the output (one at a time so stackables merge / non-stackables get slots).
	var output_id: int = int(recipe.output_item.get_meta(&"id", 0))
	for _i: int in recipe.output_amount:
		Inventory.add_item(inventory, output_id, 1)

	# Award crafting-profession xp.
	var progress: Dictionary = {}
	if recipe.xp_reward > 0:
		progress = resource.add_skill_xp(station.profession, recipe.xp_reward)

	# Quest CRAFT progress for this output item. Push unconditionally: an empty
	# messages array is a silent tracker refresh, so a "Bring N item" (COLLECT)
	# objective reflects a freshly-crafted item live, not just on menu reopen.
	var quest_updates: Array = QuestService.on_craft(resource, output_id, peer_id, instance)
	WorldServer.curr.data_push.rpc_id(peer_id, &"quest.update", {"messages": quest_updates})

	return {
		"ok": true,
		"output_id": output_id,
		"amount": recipe.output_amount,
		"profession": String(station.profession),
		"level": int(progress.get("level", level)),
		"leveled_up": progress.get("leveled_up", false),
	}
