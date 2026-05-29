extends DataRequestHandler
## Returns the player's current daily quest set + progress + claim eligibility.
## Rolls fresh dailies if stale or never rolled (first board click of the day).


func data_request_handler(peer_id: int, instance: ServerInstance, args: Dictionary) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if not player:
		return {"ok": false}
	var resource: PlayerResource = player.player_resource

	# Ensure the player has a current set (rolls if needed).
	DailyQuestService.get_or_roll(resource)

	var pool: DailyQuestPool = ResourceLoader.load(DailyQuestService.POOL_PATH) as DailyQuestPool
	if pool == null:
		return {"ok": false, "reason": "no_pool"}

	var entries: Array = []
	for entry: Variant in resource.daily_quests:
		if entry is not Dictionary:
			continue
		var d: Dictionary = entry
		var template: DailyQuestTemplate = pool.by_id(int(d.get("template_id", 0)))
		if template == null:
			continue
		var progress: int = DailyQuestService.progress_for(resource, d)
		entries.append({
			"template_id": template.template_id,
			"description": template.describe(),
			"required": template.required_amount,
			"progress": progress,
			"complete": progress >= template.required_amount,
			"claimed": bool(d.get("claimed", false)),
			"reward_xp": template.reward_xp,
			"reward_gold": template.reward_gold,
		})

	return {
		"ok": true,
		"entries": entries,
		"refresh_at_ms": resource.dailies_refresh_at_ms,
	}
