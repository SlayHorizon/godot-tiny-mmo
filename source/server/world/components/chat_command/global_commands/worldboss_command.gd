extends ChatCommand
## Spawn the live WORLD BOSS at your feet and rally the server (admin event). The
## master dashboard is owner-only, so live events are triggered in-game from here —
## this is the first command of the admin event system. See EventService.


func _init() -> void:
	command_name = "worldboss"
	command_alias = PackedStringArray(["wb"])
	command_priority = 2 # admin+
	command_usage = "/worldboss [end]"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	# /worldboss end — dispel the active boss (admin abort, no rewards distributed).
	if args.size() >= 2 and args[1].to_lower() == "end":
		return EventService.end_world_boss()

	var ws: WorldServer = server_instance.world_server
	var me_inst: ServerInstance = ws.instance_manager.find_instance_for_peer(peer_id)
	var me: Player = me_inst.get_player(peer_id) if me_inst != null else null
	if me_inst == null or me == null:
		return "Couldn't locate you."
	var map: Map = me.get_parent() as Map
	if map == null or map.replicated_props_container == null:
		return "You can't spawn a world boss here."
	return EventService.start_world_boss(me_inst, map.replicated_props_container, me.global_position)
