extends ChatCommand
## Teleport yourself to another online player — their map and position.


func _init() -> void:
	command_name = "goto"
	command_priority = 2 # admin+
	command_usage = "/goto <@account|#id>"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() != 2:
		return "Usage: " + command_usage

	var target: CommandTarget.Result = CommandTarget.resolve(args[1], peer_id, server_instance)
	if not target.ok:
		return target.error
	if not target.online:
		return "%s is offline." % target.label()
	if target.peer_id == peer_id:
		return "You're already there."

	var ws: WorldServer = server_instance.world_server
	var dest_inst: ServerInstance = ws.instance_manager.find_instance_for_peer(target.peer_id)
	var dest_player: Player = CommandTarget.player_node(target, server_instance)
	if dest_inst == null or dest_player == null:
		return "Couldn't locate %s." % target.label()

	if not ws.instance_manager.teleport_peer_to(peer_id, dest_inst, dest_player.global_position):
		return "Teleport failed."
	return "Teleported to %s." % target.label()
