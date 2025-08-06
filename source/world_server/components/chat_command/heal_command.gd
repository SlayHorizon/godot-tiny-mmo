extends ChatCommand


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() != 3:
		return "Invalid command format: /heal <target> <amount>"
	var target: int = args[1].to_int()
	var amount: int = args[2].to_int()
	if args[1] == "self":
		target = peer_id
	else:
		target = args[1].to_int()
	if not server_instance.entity_collection.has(target):
		return "Target not found."
	server_instance.update_node(
		server_instance.get_path_to(server_instance.entity_collection.get(target)),
		{^"HealthComponent:health": amount}
	)
	return "/heal " + str(amount) + " successful"
