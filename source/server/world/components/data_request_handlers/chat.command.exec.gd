extends DataRequestHandler


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var command_name: String = args.get("cmd", "")
	if command_name.is_empty():
		return {}
	
	var result: String
	var chat_command: ChatCommand = find_command(command_name, instance)
	if chat_command and has_command_permission(chat_command, peer_id, instance):
		result = chat_command.execute(
			args.get("params", []),
			peer_id,
			instance
		)
	else:
		result = "Command not found."
	# A command that does its own player-facing messaging (e.g. /worldboss announces
	# server-wide) returns "" to skip this echo — otherwise the admin gets a near-
	# duplicate "Server" line right after the announcement. Errors still come back here.
	if not result.is_empty():
		WorldServer.curr.data_push.rpc_id(
			peer_id,
			&"chat.message",
			{"text": result, "name": "Server", "id": 1}
		)
	return {command_name: args}


func find_command(command_name: String, instance: ServerInstance) -> ChatCommand:
	var command_list = instance.global_chat_commands
	if command_name in command_list:
		return command_list[command_name]

	# Alias checking
	for command: ChatCommand in command_list.values():
		if command.command_alias.has(command_name):
			return command

	return null


func has_command_permission(
	command: ChatCommand,
	peer_id: int,
	instance: ServerInstance
) -> bool:
	var player: PlayerResource = instance.world_server.connected_players.get(peer_id)
	return CommandPermissions.can_run(command, player, instance)
