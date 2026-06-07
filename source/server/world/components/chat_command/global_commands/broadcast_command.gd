extends ChatCommand
## Send a system message to every connected player across all instances.
## Use for events ("Boss spawning in 5 min"), assemblies, or server-wide notices.


func _init() -> void:
	command_name = "broadcast"
	command_priority = 2 # admin+
	command_usage = "/broadcast <message>"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() < 2:
		return "Usage: " + command_usage

	var msg: String = " ".join(args.slice(1))
	var ws: WorldServer = server_instance.world_server
	var sent: int = 0
	for connected_pid: int in ws.connected_players:
		var target: PlayerResource = ws.connected_players[connected_pid]
		if target == null:
			continue
		ws.chat_service.push_system_to_player(server_instance, target.player_id, "[Broadcast] " + msg)
		sent += 1

	return "Broadcast sent to %d player(s)." % sent
