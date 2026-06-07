extends ChatCommand
## Block an account from sending any chat (channels or DMs). Persists via MuteList
## (user://server_mutes.cfg), keyed by account so it survives a restart AND a
## character switch. Works on offline targets too — applied as soon as they
## reconnect.


func _init() -> void:
	command_name = "mute"
	command_priority = 1 # moderator+
	command_usage = "/mute <self|@account|#id> [duration] [reason]   (duration e.g. 30s, 10m, 2h, 1d; omit for permanent)"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() < 2:
		return "Usage: " + command_usage

	var target: CommandTarget.Result = CommandTarget.resolve(args[1], peer_id, server_instance)
	if not target.ok:
		return target.error
	if target.account_name.is_empty():
		return "Couldn't resolve an account for that target."

	# Optional duration in args[2]. If it parses as a valid duration token we
	# consume it; otherwise treat args[2..] as the reason (so "/mute @x spam"
	# still works without a duration).
	var args_offset: int = 2
	var duration_ms: int = 0
	var duration_label: String = "permanent"
	if args.size() > 2:
		duration_ms = ChatCommand.parse_duration_ms(args[2])
		if duration_ms > 0:
			args_offset = 3
			duration_label = args[2]
	var reason: String = " ".join(args.slice(args_offset)) if args.size() > args_offset else ""

	var ws: WorldServer = server_instance.world_server
	var moderator: PlayerResource = ws.connected_players.get(peer_id)
	var moderator_id: int = moderator.player_id if moderator else 0

	MuteList.mute(target.account_name, reason, moderator_id, duration_ms)

	# Notify the target if they're online so they understand the silence.
	if target.online:
		var notice: String = "You have been muted by a moderator (%s)." % duration_label
		if not reason.is_empty():
			notice += "\nReason: " + reason
		ws.chat_service.push_system_to_player(server_instance, target.player_id, notice)

	return "Muted %s for %s." % [target.label(), duration_label]
