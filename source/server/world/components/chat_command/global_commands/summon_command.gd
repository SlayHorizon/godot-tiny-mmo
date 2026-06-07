extends ChatCommand
## Pull an online player to your position (switching them to your map if needed).


func _init() -> void:
	command_name = "summon"
	command_priority = 2 # admin+
	command_usage = "/summon <@account|#id>"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() != 2:
		return "Usage: " + command_usage

	var target: CommandTarget.Result = CommandTarget.resolve(args[1], peer_id, server_instance)
	if not target.ok:
		return target.error
	if not target.online:
		return "%s is offline." % target.label()
	if target.peer_id == peer_id:
		return "You can't summon yourself."

	var ws: WorldServer = server_instance.world_server
	var me_inst: ServerInstance = ws.instance_manager.find_instance_for_peer(peer_id)
	var me: Player = me_inst.get_player(peer_id) if me_inst != null else null
	if me_inst == null or me == null:
		return "Couldn't locate you."

	if not ws.instance_manager.teleport_peer_to(target.peer_id, me_inst, me.global_position):
		return "Summon failed."

	ws.chat_service.push_system_to_player(server_instance, target.player_id, "You have been summoned by an admin.")
	return "Summoned %s." % target.label()
