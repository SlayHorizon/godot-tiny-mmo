extends DataRequestHandler
## Authorizes opening a shop and returns the dynamic data the client can't know on
## its own (current golds). The catalog itself is static and rendered client-side
## from the local ShopResource; the purchase is validated separately in
## shop.buy.item, so nothing here needs to send item/price data.


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var shop_id: int = int(args.get("shop_id", 0))

	# Authorization: the shop must be sold by a merchant present in the player's own
	# map — not just a valid id anywhere. Later, tighten to radius proximity via the
	# merchant's Area2D (body_entered presence). Faction/quest gating slots in here.
	if instance.instance_map.get_shop(shop_id) == null:
		return {"ok": false}

	var golds: int
	var player_resource: PlayerResource = instance.world_server.connected_players.get(peer_id)
	if player_resource:
		golds = player_resource.golds

	return {"ok": true, "golds": golds}
