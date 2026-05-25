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

	# Only golds are implemented; other currencies are reserved for future events.
	if int(entry.get("currency", ShopEntry.Currency.GOLDS)) != ShopEntry.Currency.GOLDS:
		return {"ok": false, "reason": "currency_not_supported"}

	var total: int = int(entry.get("price", 0)) * amount
	if player.player_resource.golds < total:
		return {"ok": false}

	player.player_resource.golds -= total
	# Add one at a time so stackable items merge and non-stackable get separate slots.
	for i: int in amount:
		Inventory.add_item(player.player_resource.inventory, item_id, 1)
	return {"ok": true, "golds": player.player_resource.golds}
