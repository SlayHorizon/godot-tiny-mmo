extends ChatCommand
## Lift a chat mute. Works on offline targets too.


func _init() -> void:
	command_name = "unmute"
	command_priority = 1 # moderator+


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() != 2:
		return "Usage: /unmute <player_id>"

	var target_id: int = args[1].to_int()
	if target_id <= 0:
		return "Invalid player id."

	if not MuteList.unmute(target_id):
		return "Player #%d is not muted." % target_id

	# Notify the target if they're online so they know chat is open again.
	var ws: WorldServer = server_instance.world_server
	var target_peer_id: int = ws.player_id_to_peer_id.get(target_id, 0)
	if target_peer_id != 0:
		var target: PlayerResource = ws.connected_players.get(target_peer_id)
		if target:
			ws.chat_service.push_system_to_player(server_instance, target.player_id, "You have been unmuted.")
			return "Unmuted %s (#%d)." % [target.display_name, target.player_id]

	return "Unmuted #%d." % target_id
