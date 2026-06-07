extends ChatCommand
## Jump straight to a level (1–20). Useful for testing high-level content without
## grinding XP. Resets experience to 0 within the new level and grants the
## attribute points the jump would have earned.


func _init() -> void:
	command_name = "setlevel"
	command_priority = 100 # senior_admin
	command_usage = "/setlevel <self|@account|#id> <level>"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() != 3:
		return "Usage: " + command_usage

	var target: CommandTarget.Result = CommandTarget.resolve(args[1], peer_id, server_instance)
	if not target.ok:
		return target.error
	if not target.online:
		return "%s must be online." % target.label()

	var new_level: int = args[2].to_int()
	if new_level < 1 or new_level > 20:
		return "Level must be between 1 and 20."

	var ws: WorldServer = server_instance.world_server
	var res: PlayerResource = target.resource
	var level_before: int = res.level
	res.level = new_level
	res.experience = 0
	# Compensate the attribute-point gain that would have happened naturally.
	var levels_jumped: int = new_level - level_before
	if levels_jumped > 0:
		res.available_attributes_points += levels_jumped * PlayerResource.ATTRIBUTE_POINTS_PER_LEVEL

	ws.data_push.rpc_id(target.peer_id, &"combat.reward", {
		"xp": 0,
		"level": res.level,
		"levels_gained": maxi(0, levels_jumped),
		"points_gained": maxi(0, levels_jumped * PlayerResource.ATTRIBUTE_POINTS_PER_LEVEL),
		"experience": 0,
		"xp_to_next": res.level_xp_to_next(),
		"loot": [],
	})

	if levels_jumped > 0:
		var inst: ServerInstance = ws.instance_manager.find_instance_for_peer(target.peer_id)
		LevelMilestoneService.on_levels_gained(res, level_before, new_level, inst)

	return "Set %s to level %d." % [target.label(), new_level]
