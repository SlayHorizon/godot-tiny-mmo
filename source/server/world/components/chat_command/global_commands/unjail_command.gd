extends ChatCommand
## Release a jailed player. If they're online and currently in the jail instance,
## they stay there — they have to walk out through a warper now that the jail flag
## is cleared. Keeps the release graceful (no surprise teleport). Account-keyed.


func _init() -> void:
	command_name = "unjail"
	command_priority = 2 # admin+
	command_usage = "/unjail <self|@account|#id>"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() != 2:
		return "Usage: " + command_usage

	var target: CommandTarget.Result = CommandTarget.resolve(args[1], peer_id, server_instance)
	if not target.ok:
		return target.error
	if target.account_name.is_empty():
		return "Couldn't resolve an account for that target."

	if not JailList.release(target.account_name):
		return "%s is not jailed." % target.label()

	var ws: WorldServer = server_instance.world_server
	if target.online:
		ws.chat_service.push_system_to_player(
			server_instance, target.player_id,
			"You have been released from jail. Walk to a warper to leave the area."
		)
	return "Released %s." % target.label()
