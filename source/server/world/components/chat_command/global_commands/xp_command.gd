extends ChatCommand
## Grant experience to a player. Triggers the same level-up + milestone flow as a
## kill or quest turn-in, so it's a clean way to fast-forward through quest gates.


func _init() -> void:
	command_name = "xp"
	command_priority = 100 # senior_admin
	command_usage = "/xp <self|@account|#id> <amount>"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() != 3:
		return "Usage: " + command_usage

	var target: CommandTarget.Result = CommandTarget.resolve(args[1], peer_id, server_instance)
	if not target.ok:
		return target.error
	if not target.online:
		return "%s must be online to grant XP." % target.label()

	var amount: int = args[2].to_int()
	if amount == 0:
		return "Invalid XP amount."

	var ws: WorldServer = server_instance.world_server
	var res: PlayerResource = target.resource
	var level_before: int = res.level
	var progress: Dictionary = res.add_experience(amount)

	# Push the same combat.reward payload a kill/quest does so the client gets
	# the XP bar + level-up handling for free.
	ws.data_push.rpc_id(target.peer_id, &"combat.reward", {
		"xp": amount,
		"level": int(progress.get("level", 1)),
		"levels_gained": int(progress.get("levels_gained", 0)),
		"points_gained": int(progress.get("points_gained", 0)),
		"experience": res.experience,
		"xp_to_next": res.level_xp_to_next(),
		"loot": [],
	})

	if int(progress.get("levels_gained", 0)) > 0:
		var inst: ServerInstance = ws.instance_manager.find_instance_for_peer(target.peer_id)
		LevelMilestoneService.on_levels_gained(res, level_before, int(progress.get("level", 1)), inst)

	return "Granted %d XP to %s (now level %d, %d/%d)." % [
		amount, target.label(), res.level, res.experience, res.level_xp_to_next()
	]
