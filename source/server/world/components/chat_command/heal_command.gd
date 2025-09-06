extends ChatCommand


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() != 3:
		return "Invalid command format: /heal <target> <amount>"
	
	var target: int = peer_id if args[1] == "self" else args[1].to_int()
	var amount: int = args[2].to_int()
	
	if server_instance.get_player(target) == null:
		return "Target not found."
	
	var error: bool = server_instance.set_player_attr_current(target, &"health", amount)
	return ("/heal %s %s" % [str(target), str(amount)]) + (" successful" if error else " failed")
