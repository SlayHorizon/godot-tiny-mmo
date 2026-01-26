extends ChatCommand


func _init():
	command_name = 'getid'
	command_priority = 0


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() == 2:
		match args[1]:
			"network":
				return str(peer_id)
			"character":
				return str(server_instance.world_server.connected_players[peer_id].player_id)
			"instance":
				return server_instance.instance_resource.instance_name
	return "Invalid command format: /getid network/character/instance"
