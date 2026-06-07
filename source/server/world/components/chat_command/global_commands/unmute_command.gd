extends ChatCommand
## Lift a chat mute. Account-keyed; works on offline targets too.


func _init() -> void:
	command_name = "unmute"
	command_priority = 1 # moderator+
	command_usage = "/unmute <self|@account|#id>"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() != 2:
		return "Usage: " + command_usage

	var target: CommandTarget.Result = CommandTarget.resolve(args[1], peer_id, server_instance)
	if not target.ok:
		return target.error
	if target.account_name.is_empty():
		return "Couldn't resolve an account for that target."

	if not MuteList.unmute(target.account_name):
		return "%s is not muted." % target.label()

	var ws: WorldServer = server_instance.world_server
	if target.online:
		ws.chat_service.push_system_to_player(server_instance, target.player_id, "You have been unmuted.")
	return "Unmuted %s." % target.label()
