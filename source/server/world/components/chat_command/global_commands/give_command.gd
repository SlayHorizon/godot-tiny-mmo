extends ChatCommand


func _init() -> void:
	command_name = "give"
	command_priority = 100 # senior_admin


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() < 2 or args.size() > 3:
		return "Invalid command format: /give <item_id> [amount]"

	var item_id: int = args[1].to_int()
	var amount: int = args[2].to_int() if args.size() == 3 else 1
	if item_id <= 0 or amount <= 0:
		return "Invalid item id or amount."

	var item: Item = ContentRegistryHub.load_by_id(&"items", item_id) as Item
	if item == null:
		return "No item with id %d." % item_id

	var player: PlayerResource = server_instance.world_server.connected_players.get(peer_id)
	if player == null:
		return "Player not found."

	Inventory.add_item(player.inventory, item_id, amount)
	return "Gave %d x %s (id %d)." % [amount, str(item.item_name), item_id]
