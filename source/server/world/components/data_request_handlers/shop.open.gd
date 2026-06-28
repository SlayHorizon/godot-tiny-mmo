extends DataRequestHandler
## Authorizes opening a shop. The catalog is static and rendered client-side from the
## local ShopResource; gold (a currency item) is read by the client from its inventory;
## purchases are validated in shop.buy.item. So this only needs to gate access.


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var shop_key: StringName = StringName(str(args.get("shop_key", "")))

	# Authorization: the shop must be sold by a merchant present in the player's own
	# map — not just a valid key anywhere. Later, tighten to radius proximity via the
	# merchant's Area2D (body_entered presence). Faction/quest gating slots in here.
	if instance.instance_map.get_shop(shop_key) == null:
		return {"ok": false}

	return {"ok": true}
