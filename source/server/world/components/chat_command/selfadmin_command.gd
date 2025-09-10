extends ChatCommand

# Only running in debug mode for now.
func execute(_args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	server_instance.world_server.connected_players[peer_id].server_roles["senior_admin"] = {}
	return "Yes admin"
