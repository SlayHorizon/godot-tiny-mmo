extends DataRequestHandler


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var shop_id: StringName = StringName(str(args.get("shop_id", "default")))
	var catalog: Dictionary = ShopCatalog.get_items(shop_id)
	if catalog.is_empty():
		return {}
	var items: Array = []
	for item_id: int in catalog:
		items.append({"id": item_id, "price": catalog[item_id]})
	return {"items": items}
