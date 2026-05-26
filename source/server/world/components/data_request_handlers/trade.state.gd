extends DataRequestHandler


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var table: TradeTable = instance.instance_map.get_trade_table(int(args.get("table", 0)))
	if table == null:
		return {}
	return TradeService.build_state(table)
