extends DataRequestHandler
## Sets a seated player's full offer ({ "items": {item_id: amount}, "gold": int }).
## Validated against current inventory (not removed until the swap). Re-confirms reset.


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if not player:
		return {"ok": false}

	var table: TradeTable = instance.instance_map.get_trade_table(int(args.get("table", 0)))
	if table == null or not table.seat_players.has(player):
		return {"ok": false}

	var inventory: Dictionary = player.player_resource.inventory

	var gold: int = maxi(0, int(args.get("gold", 0)))
	if Inventory.count(inventory, Economy.gold_id()) < gold:
		return {"ok": false, "reason": "gold"}

	# Keep only owned, positive, non-currency items.
	var items: Dictionary = {}
	var requested: Dictionary = args.get("items", {})
	for key in requested:
		var item_id: int = int(key)
		var amount: int = int(requested[key])
		if item_id <= 0 or amount <= 0 or item_id == Economy.gold_id():
			continue
		if Inventory.count(inventory, item_id) < amount:
			return {"ok": false, "reason": "items"}
		items[item_id] = amount

	if items.size() > TradeTable.MAX_OFFER_ITEMS:
		return {"ok": false, "reason": "too_many"}

	table.server_set_offer(player, items, gold)
	TradeService.broadcast(instance, table)
	return {"ok": true}
