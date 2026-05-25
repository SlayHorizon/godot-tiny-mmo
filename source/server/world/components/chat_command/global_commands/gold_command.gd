extends ChatCommand


func _init() -> void:
	command_name = "gold"
	# TODO: raise to admin-only (priority) before release. 0 = anyone, for prototyping.
	command_priority = 0


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() != 2:
		return "Invalid command format: /gold <amount>"

	var amount: int = args[1].to_int()
	var player: PlayerResource = server_instance.world_server.connected_players.get(peer_id)
	if player == null:
		return "Player not found."

	# Gold is a currency item; add it to the inventory.
	Inventory.add_item(player.inventory, Economy.gold_id(), amount)
	return "Added %d gold. New balance: %d." % [amount, Inventory.count(player.inventory, Economy.gold_id())]
