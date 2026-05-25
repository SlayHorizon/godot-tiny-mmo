extends DataRequestHandler


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var item_id: int = int(args.get("id", 0))

	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if not player:
		return {}
	var inventory: Dictionary = player.player_resource.inventory
	# Must own the item to act on it.
	if not Inventory.has_item(inventory, item_id):
		return {}

	var item: Item = ContentRegistryHub.load_by_id(&"items", item_id)
	if not item:
		return {}

	if item is GearItem and item.can_equip(player):
		var slot_key: StringName = item.slot.key
		var previous_id: int = int(player.equipment_component.slots.values.get(slot_key, 0))
		if not player.equipment_component.equip_item(item_id):
			return {}
		# Move the item out of inventory; return any swapped-out gear to it.
		Inventory.remove_one_by_id(inventory, item_id)
		if previous_id > 0:
			Inventory.add_item(inventory, previous_id, 1)
		player.player_resource.equipment[slot_key] = item_id
	elif item is ConsumableItem:
		item.on_use(player)
	return {}
