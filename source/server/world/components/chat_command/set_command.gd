extends ChatCommand


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() != 4:
		return "Invalid command format: /set <target> <path> <value>"
	
	var target: int = peer_id if args[1] == "self" else args[1].to_int()
	var path: NodePath = args[2]
	var value: Variant = str_to_var(args[3])
	
	#print_debug(value)
	if path.is_empty() or not value:
		return "Invalid command format: /set <target> <path> <value>"
	
	var player: Player = server_instance.get_player(peer_id)
	if not player:
		return "Target not found."
	
	var error: bool = false
	var current_value: Variant = player.get_indexed(path)
	if current_value == null:
		error = true
	else:
		var typeof_value: int = typeof(current_value)
		value = type_convert(value, typeof_value)
		if value:
			player.syn.set_by_path(path, value)
		else:
			error = true
	print_debug(
		("/set %s %s" % [str(target), str(value)]) + (" successful" if not error else " failed")
	)
	return ("/set %s %s" % [str(target), str(value)]) + (" successful" if not error else " failed")
