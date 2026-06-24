extends DataRequestHandler


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if not player:
		return {"ok": false}

	var shop_id: int = int(args.get("shop_id", 0))
	var item_id: int = int(args.get("id", 0))
	var amount: int = int(args.get("amount", 1))
	if item_id <= 0 or amount <= 0:
		return {"ok": false}

	# Resolve the shop from a merchant present in the player's map (authoritative +
	# verifies the player is at the shop's map), not from a client-trusted id.
	var shop: ShopResource = instance.instance_map.get_shop(shop_id)
	if not shop or not shop.allows_buying():
		return {"ok": false}

	var entry: Dictionary = shop.entry_for(item_id)
	if entry.is_empty():
		return {"ok": false}

	var inventory: Dictionary = player.player_resource.inventory
	var currency_id: int = int(entry.get("currency_id", 0))
	var total: int = int(entry.get("price", 0)) * amount
	# Pay with the currency item (gold by default).
	if currency_id <= 0 or not Inventory.remove_amount_by_id(inventory, currency_id, total):
		return {"ok": false}

	# Add one at a time so stackable items merge and non-stackable get separate slots.
	for i: int in amount:
		Inventory.add_item(inventory, item_id, 1)

	# Silent quest refresh: a bought item may satisfy a "Bring N item" (COLLECT)
	# objective, which has no advance event of its own. Empty messages = no toast,
	# just a HUD tracker re-fetch.
	WorldServer.curr.data_push.rpc_id(peer_id, &"quest.update", {"messages": []})
	return {"ok": true}
