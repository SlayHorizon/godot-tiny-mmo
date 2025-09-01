extends ChatCommand


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() != 3:
		return "Invalid command format: /size <target|self> <size>"
	
	var target: int = peer_id if args[1] == "self" else args[1].to_int()
	var amount: int = clampi(args[2].to_int(), 1, 4)
	
	if server_instance.get_player(target) == null:
		return "Target not found."
	
	var ok := server_instance.set_player_path_value(target, ^":scale", Vector2(amount, amount))
	return ("/size %s %s" % [str(target), str(amount)]) + (" successful" if ok else " failed")
