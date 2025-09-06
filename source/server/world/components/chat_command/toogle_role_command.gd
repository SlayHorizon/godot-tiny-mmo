extends ChatCommand


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if not args.size() == 3:
		return "Format <role> <active/desactivate>"
	var player: PlayerResource = server_instance.world_server.connected_players.get(peer_id, null)
	if not player:
		return "Unknown peer."
	if player.server_roles.has(args[1]):
		player.server_roles["active"] = true if args[2] == "active" else false 
		return "Your role state has been changed."
	return "You don't have this role."
