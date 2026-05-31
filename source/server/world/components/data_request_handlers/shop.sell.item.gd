extends DataRequestHandler
## Sell an inventory slot to a vendor for golds. Any merchant buys any item with a
## vendor_value > 0 (universal "dump junk for gold"); the sell price is the item's
## vendor_value, NOT shop-defined.


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if not player:
		return {"ok": false}

	# Authorization: player must be at a real merchant in their map (same as buying),
	# and that merchant must accept generic sells. Specialty vendors (those with
	# any accepted_trades) refuse junk — the player must use shop.trade.item.
	var shop_id: int = int(args.get("shop_id", 0))
	var shop: ShopResource = instance.instance_map.get_shop(shop_id)
	if shop == null or not shop.allows_selling() or shop.has_trades():
		return {"ok": false}

	var slot_uid: int = int(args.get("slot_uid", 0))
	var amount: int = int(args.get("amount", 1))
	if amount <= 0:
		return {"ok": false}

	var inventory: Dictionary = player.player_resource.inventory
	if not inventory.has(slot_uid):
		return {"ok": false}

	var item_id: int = int(inventory[slot_uid].get("id", 0))
	var item: Item = ContentRegistryHub.load_by_id(&"items", item_id)
	if item == null or item.vendor_value <= 0:
		# Not sellable to vendors (quest/bound/junk-safe).
		return {"ok": false}

	# Refuse to sell an equipped item (equip is item_id-based; selling would leave
	# the equipment referencing gear the player no longer owns). Unequip first.
	if item_id in player.equipment_component.slots.values.values():
		return {"ok": false, "reason": "equipped"}

	var removed: int = Inventory.remove_from_slot(inventory, slot_uid, amount)
	if removed <= 0:
		return {"ok": false}

	# Pay the player in gold (a currency item).
	Inventory.add_item(inventory, Economy.gold_id(), item.vendor_value * removed)
	return {"ok": true, "removed": removed}
