extends ChatCommand
## Block a player from sending any chat (channels or DMs). Persists via MuteList
## (user://server_mutes.cfg) so it survives a restart. Works on offline targets
## too — they'll be muted as soon as they reconnect.


func _init() -> void:
	command_name = "mute"
	command_priority = 1 # moderator+


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() < 2:
		return "Usage: /mute <player_id> [duration] [reason]   (duration e.g. 30s, 10m, 2h, 1d; omit for permanent)"

	var target_id: int = args[1].to_int()
	if target_id <= 0:
		return "Invalid player id."

	# Optional duration in args[2]. If it parses as a valid duration token we
	# consume it; otherwise treat args[2..] as the reason (so "/mute id spam"
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

	# If target is online, notify them so they understand why chat is silent.
	# Resolve a nicer display name for the confirmation too.
	var target_name: String = "#%d" % target_id
	var target_peer_id: int = ws.player_id_to_peer_id.get(target_id, 0)
	if target_peer_id != 0:
		var target: PlayerResource = ws.connected_players.get(target_peer_id)
		if target:
			target_name = "%s @%s (#%d)" % [target.display_name, target.account_name, target.player_id]
			var notice: String = "You have been muted by a moderator (%s)." % duration_label
			if not reason.is_empty():
				notice += "\nReason: " + reason
			ws.chat_service.push_system_to_player(server_instance, target.player_id, notice)

	MuteList.mute(target_id, reason, moderator_id, duration_ms)
	return "Muted %s for %s." % [target_name, duration_label]
