extends ChatCommand
## /help          → list every command the caller may run.
## /help <name>   → show that command's usage (and aliases), if they can run it.


func _init() -> void:
	command_name = "help"
	command_priority = 0
	command_alias = ["h"]
	command_usage = "/help [command]"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	var player: PlayerResource = server_instance.world_server.connected_players.get(peer_id)
	var commands: Dictionary = server_instance.global_chat_commands

	# /help <command> — usage for one command (only if the caller may run it, so
	# /help can't be used to enumerate staff commands).
	if args.size() >= 2:
		var query: String = args[1].to_lower().trim_prefix("/")
		var command: ChatCommand = _lookup(query, commands)
		if command == null or not CommandPermissions.can_run(command, player, server_instance):
			return "Unknown command '%s'. Type /help for the list." % query
		var usage: String = command.command_usage if not command.command_usage.is_empty() else "/" + command.command_name
		if not command.command_alias.is_empty():
			usage += "\nAliases: " + ", ".join(command.command_alias)
		return usage

	# /help — list every command the caller may run, sorted by name.
	var names: Array = commands.keys()
	names.sort()
	var lines: PackedStringArray = []
	for command_name: String in names:
		var command: ChatCommand = commands[command_name]
		if CommandPermissions.can_run(command, player, server_instance):
			var entry: String = "/" + command_name
			if not command.command_alias.is_empty():
				entry += " (" + ", ".join(command.command_alias) + ")"
			lines.append(entry)

	if lines.is_empty():
		return "No commands available."
	return "Available commands (type /help <command> for usage):\n" + "\n".join(lines)


func _lookup(name: String, commands: Dictionary) -> ChatCommand:
	if commands.has(name):
		return commands[name]
	for command: ChatCommand in commands.values():
		if command.command_alias.has(name):
			return command
	return null
