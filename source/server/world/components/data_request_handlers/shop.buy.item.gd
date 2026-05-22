extends DataRequestHandler


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if not player:
		return {"ok": false}

	var shop_id: StringName = StringName(str(args.get("shop_id", "default")))
	var item_id: int = args.get("id", 0)
	if item_id <= 0:
		return {"ok": false}

	var price: int = ShopCatalog.get_price(shop_id, item_id)
	if price < 0:
		return {"ok": false}

	if player.player_resource.golds < price:
		return {"ok": false}

	player.player_resource.golds -= price
	player.player_resource.inventory[item_id] = {"a": 1}
	return {"ok": true, "golds": player.player_resource.golds}
