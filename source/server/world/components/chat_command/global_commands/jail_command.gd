extends ChatCommand
## Send a player to the jail instance until released (or until a timed sentence
## expires). Account-keyed, so a character switch can't escape it. They can still
## DM friends and chat to others jailed with them, but warpers won't let them
## out. A lighter alternative to a full account ban for low-level infractions.


func _init() -> void:
	command_name = "jail"
	command_priority = 2 # admin+
	command_usage = "/jail <self|@account|#id> [duration] [reason]   (duration e.g. 30s, 10m, 2h, 1d; omit for indefinite)"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() < 2:
		return "Usage: " + command_usage

	var target: CommandTarget.Result = CommandTarget.resolve(args[1], peer_id, server_instance)
	if not target.ok:
		return target.error
	if target.account_name.is_empty():
		return "Couldn't resolve an account for that target."

	# Same optional-duration parsing as /mute.
	var args_offset: int = 2
	var duration_ms: int = 0
	var duration_label: String = "indefinite"
	if args.size() > 2:
		duration_ms = ChatCommand.parse_duration_ms(args[2])
		if duration_ms > 0:
			args_offset = 3
			duration_label = args[2]
	var reason: String = " ".join(args.slice(args_offset)) if args.size() > args_offset else ""

	var ws: WorldServer = server_instance.world_server
	var admin: PlayerResource = ws.connected_players.get(peer_id)
	var admin_id: int = admin.player_id if admin else 0

	# Persist first so the entry exists even if the teleport fails (e.g. jail
	# map not authored yet) — the player is redirected on next login.
	JailList.jail(target.account_name, reason, admin_id, duration_ms)

	var teleported: bool = false
	if target.online:
		teleported = ws.instance_manager.send_player_to_jail(target.peer_id)
		var notice: String = "You have been jailed by an admin (%s)." % duration_label
		if not reason.is_empty():
			notice += "\nReason: " + reason
		ws.chat_service.push_system_to_player(server_instance, target.player_id, notice)

	var suffix: String = "" if teleported or not target.online else " (no jail map configured — they'll be sent on next login)"
	return "Jailed %s for %s.%s" % [target.label(), duration_label, suffix]
