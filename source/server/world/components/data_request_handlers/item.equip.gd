extends DataRequestHandler


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var item_id: int = args.get("id", 0)
	
	# Check if player has the weapon
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if player and player.player_resource.inventory.has(item_id):
		var item: Item = ContentRegistryHub.load_by_id(&"items", item_id)
		if item:
			if item is GearItem and item.can_equip(player):
				player.state_synchronizer.set_by_path(^"EquipmentComponent:mainhand_id", item_id)
			elif item is ConsumableItem:
				item.on_use(player)
	return {}
