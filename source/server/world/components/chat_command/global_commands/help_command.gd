extends ChatCommand


func _init():
	command_name = 'help'
	command_priority = 0
	command_alias = ['h']


func execute(_args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	var player: PlayerResource = server_instance.world_server.connected_players.get(peer_id)

	# List every command the player is actually allowed to run, sorted by name.
	var names: Array = server_instance.global_chat_commands.keys()
	names.sort()

	var lines: PackedStringArray = []
	for command_name: String in names:
		var command: ChatCommand = server_instance.global_chat_commands[command_name]
		if CommandPermissions.can_run(command, player, server_instance):
			var entry: String = "/" + command_name
			if not command.command_alias.is_empty():
				entry += " (" + ", ".join(command.command_alias) + ")"
			lines.append(entry)

	if lines.is_empty():
		return "No commands available."
	return "Available commands:\n" + "\n".join(lines)
