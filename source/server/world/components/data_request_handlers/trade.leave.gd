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

	if table.server_remove_player(player):
		TradeService.broadcast(instance, table)
	return {"ok": true}
