extends DataRequestHandler
## Specialty vendor trade: hand over `bundles * trade.amount` of `trade.item`
## in exchange for `bundles * trade.payout` of `trade.currency_item` (default
## gold). The exchange rate is set by the vendor (ShopTrade) rather than by the
## item's vendor_value. See shop.sell.item for the generic-junk path.


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if not player:
		return {"ok": false}

	# Authorize: the shop must be present in the player's current map.
	var shop_id: int = int(args.get("shop_id", 0))
	var shop: ShopResource = instance.instance_map.get_shop(shop_id)
	if shop == null:
		return {"ok": false}

	# Resolve the trade by its array index (the client renders trades in order).
	var trade_index: int = int(args.get("trade_index", -1))
	if trade_index < 0 or trade_index >= shop.accepted_trades.size():
		return {"ok": false}
	var trade: ShopTrade = shop.accepted_trades[trade_index]
	if trade == null or trade.item == null or trade.amount <= 0:
		return {"ok": false}

	var bundles: int = maxi(1, int(args.get("bundles", 1)))
	var item_id: int = int(trade.item.get_meta(&"id", 0))
	if item_id <= 0:
		return {"ok": false}

	var inventory: Dictionary = player.player_resource.inventory
	var total_needed: int = trade.amount * bundles
	if Inventory.count(inventory, item_id) < total_needed:
		return {"ok": false, "reason": "not_enough"}

	# Pull the items, then pay out. remove_amount_by_id is all-or-nothing.
	if not Inventory.remove_amount_by_id(inventory, item_id, total_needed):
		return {"ok": false}

	var currency_id: int = (
		int(trade.currency_item.get_meta(&"id", 0)) if trade.currency_item
		else Economy.gold_id()
	)
	Inventory.add_item(inventory, currency_id, trade.payout * bundles)
	return {"ok": true, "bundles": bundles}
