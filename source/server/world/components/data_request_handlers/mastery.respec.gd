extends DataRequestHandler
## Wipes a category's spent points + loadout pick. Free during alpha (testers
## should experiment); revisit pricing post-alpha if hopping feels abusive.


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var category: StringName = StringName(str(args.get("category", "")))
	if category.is_empty():
		return {"ok": false}

	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if not player:
		return {"ok": false}

	var result: Dictionary = MasteryService.reset(player.player_resource, category)
	if result.get("ok", false):
		# Unmount the lost special / strip now-unowned passives immediately.
		MasteryService.refresh(player)
	return result
