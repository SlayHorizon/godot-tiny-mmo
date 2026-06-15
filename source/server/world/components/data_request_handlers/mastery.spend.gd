extends DataRequestHandler
## Buys one mastery-tree node. All gating (tier level, point budget,
## already-owned) lives in MasteryService.spend.


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var category: StringName = StringName(str(args.get("category", "")))
	var node_id: StringName = StringName(str(args.get("node", "")))
	if category.is_empty() or node_id.is_empty():
		return {"ok": false}

	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if not player:
		return {"ok": false}

	var result: Dictionary = MasteryService.spend(player.player_resource, category, node_id)
	if result.get("ok", false):
		# Learning an upgrade bumps an equipped lower tier up to the new best,
		# so the slot now shows + fires the move you just unlocked.
		MasteryService.normalize_loadout(player.player_resource, category)
		# A passive node bought while wielding the category applies right away.
		MasteryService.refresh(player)
	return result
