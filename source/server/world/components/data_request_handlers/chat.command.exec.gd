extends DataRequestHandler


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var command_name: String = "/" + args.get("cmd", "")
	if command_name.is_empty():
		return {}
	
	var result: String
	var chat_command: ChatCommand = find_command(command_name, instance)
	if chat_command and has_command_permission(command_name, peer_id, instance):
		result = chat_command.execute(
			args.get("params", []),
			peer_id,
			instance
		)
	else:
		result = "Command not found."
	instance.data_push.rpc_id(
		peer_id,
		&"chat.message",
		{"text": result, "name": "Server", "id": 1}
	)
	return {command_name: args}


func find_command(command_name: String, instance: ServerInstance) -> ChatCommand:
	if instance.local_chat_commands.has(command_name):
		return instance.local_chat_commands.get(command_name)
	return instance.global_chat_commands.get(command_name)


# Can be refactored to be more efficient?
func has_command_permission(
	command_name: String,
	peer_id: int,
	instance: ServerInstance
) -> bool:
	var player: PlayerResource = instance.world_server.connected_players.get(peer_id)
	if not player:
		return false
	
	# Check if command is possible by default.
	# Check in current instance.
	var default_role_data: Dictionary = instance.local_role_definitions.get("default", {})
	if default_role_data and command_name in default_role_data.get("commands", []):
		return true
	
	# Check server-wide.
	default_role_data = instance.global_role_definitions.get("default", {})
	if default_role_data and command_name in default_role_data.get("commands", []):
		return true
	
	# Check if player has roles in current instance.
	for role: String in instance.local_role_assignments.get(peer_id, []):
		var role_data: Dictionary = instance.local_role_definitions.get(role)
		if role_data and command_name in role_data.get("commands", []):
			return true
		# Check if role is defined locally.
		if instance.local_role_definitions.has(role) and instance.local_role_definitions[role].has("commands"):
			# Check if roole has permission.
			if instance.local_role_definitions[role]["commands"].has(command_name):
				return true
	
	# Same but for server-wide roles.
	for role: String in player.server_roles:
		var role_data: Dictionary = instance.global_role_definitions.get(role)
		if role_data and command_name in role_data.get("commands", []):
			return true
	return false
