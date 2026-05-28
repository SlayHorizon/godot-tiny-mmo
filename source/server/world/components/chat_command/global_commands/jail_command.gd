extends ChatCommand
## Send a player to the jail instance until released (or until a timed sentence
## expires). They can still DM friends and chat to others jailed with them, but
## warpers won't let them out. A lighter alternative to a full account ban for
## low-level infractions.


func _init() -> void:
	command_name = "jail"
	command_priority = 2 # admin+


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() < 2:
		return "Usage: /jail <player_id> [duration] [reason]   (duration e.g. 30s, 10m, 2h, 1d; omit for indefinite)"

	var target_id: int = args[1].to_int()
	if target_id <= 0:
		return "Invalid player id."

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
	# map not authored yet) — the player will be redirected on next login.
	JailList.jail(target_id, reason, admin_id, duration_ms)

	var target_name: String = "#%d" % target_id
	var target_peer_id: int = ws.player_id_to_peer_id.get(target_id, 0)
	var teleported: bool = false
	if target_peer_id != 0:
		var target: PlayerResource = ws.connected_players.get(target_peer_id)
		if target:
			target_name = "%s @%s (#%d)" % [target.display_name, target.account_name, target.player_id]
			teleported = ws.instance_manager.send_player_to_jail(target_peer_id)
			var notice: String = "You have been jailed by an admin (%s)." % duration_label
			if not reason.is_empty():
				notice += "\nReason: " + reason
			ws.chat_service.push_system_to_player(server_instance, target.player_id, notice)

	var suffix: String = "" if teleported or target_peer_id == 0 else " (no jail map configured — they'll be sent on next login)"
	return "Jailed %s for %s.%s" % [target_name, duration_label, suffix]
