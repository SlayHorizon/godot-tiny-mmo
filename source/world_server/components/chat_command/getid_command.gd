extends ChatCommand


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> bool:
	if args.size() == 2:
		match args[1]:
			"network":
				server_instance.fetch_message.rpc_id(peer_id, str(peer_id), 1)
			"character":
				server_instance.fetch_message.rpc_id(
					peer_id,
					str(server_instance.world_server.connected_players[peer_id].player_id),
					1
				)
			"instance":
				server_instance.fetch_message.rpc_id(
					peer_id,
					server_instance.instance_resource.instance_name,
					1
				)
			_:
				return false
	return true
