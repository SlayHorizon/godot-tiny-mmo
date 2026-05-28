extends ChatCommand
## Release a jailed player. If they're online and currently in the jail
## instance, they stay there — they have to walk out through a warper now
## that the jail flag is cleared. Keeps the release graceful (no surprise
## teleport across the world).


func _init() -> void:
	command_name = "unjail"
	command_priority = 2 # admin+


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() != 2:
		return "Usage: /unjail <player_id>"

	var target_id: int = args[1].to_int()
	if target_id <= 0:
		return "Invalid player id."

	if not JailList.release(target_id):
		return "Player #%d is not jailed." % target_id

	var ws: WorldServer = server_instance.world_server
	var target_peer_id: int = ws.player_id_to_peer_id.get(target_id, 0)
	if target_peer_id != 0:
		var target: PlayerResource = ws.connected_players.get(target_peer_id)
		if target:
			ws.chat_service.push_system_to_player(
				server_instance, target.player_id,
				"You have been released from jail. Walk to a warper to leave the area."
			)
			return "Released %s (#%d)." % [target.display_name, target.player_id]

	return "Released #%d." % target_id
