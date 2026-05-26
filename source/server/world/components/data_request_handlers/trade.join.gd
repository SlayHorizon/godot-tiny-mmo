extends DataRequestHandler


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if not player:
		return {"ok": false}

	var table: TradeTable = instance.instance_map.get_trade_table(int(args.get("table", 0)))
	if table == null:
		return {"ok": false}

	# Must be at the table to sit (and the table auto-removes you if you wander off).
	if player.global_position.distance_to(table.global_position) > table.seat_range:
		return {"ok": false, "reason": "too_far"}

	if table.seat_players.has(player):
		return {"ok": true} # already seated, no extra charge

	var seat: int = table.seat_players.find(null)
	if seat == -1:
		return {"ok": false, "reason": "full"}

	# Join tax (gold sink), charged once whether or not the trade completes.
	var inventory: Dictionary = player.player_resource.inventory
	if Inventory.count(inventory, Economy.gold_id()) < table.join_cost:
		return {"ok": false, "reason": "gold"}
	if table.join_cost > 0:
		Inventory.remove_amount_by_id(inventory, Economy.gold_id(), table.join_cost)

	table.seat_players[seat] = player
	TradeService.broadcast(instance, table)
	return {"ok": true}
