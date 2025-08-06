extends ChatCommand


func execute(_args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	var player_roles: PackedStringArray
	var possible_commands: PackedStringArray

	player_roles = server_instance.local_role_assignments.get(peer_id, [])
	player_roles.append("default")
	for role: String in player_roles:
		var role_data: Dictionary = server_instance.local_role_definitions.get(role, {})
		if role_data:
			possible_commands.append_array(role_data.get("commands", []))
	
	player_roles = server_instance.world_server.connected_players[peer_id].server_roles.keys() as PackedStringArray
	player_roles.append("default")
	for role: String in player_roles:
		var role_data: Dictionary = server_instance.global_role_definitions.get(role, {})
		if role_data:
			possible_commands.append_array(role_data.get("commands", []))

	return "\n".join(possible_commands)
