extends ChatCommand
## Grant experience to a player. Triggers the same level-up + milestone flow as a
## kill or quest turn-in, so it's a clean way to fast-forward through quest gates.
## With a trailing weapon category (wand / sword / ...), grants WEAPON MASTERY
## xp for that category instead of character xp.


func _init() -> void:
	command_name = "xp"
	command_priority = 100 # senior_admin
	command_usage = "/xp <self|@account|#id> <amount> [mastery category, e.g. wand]"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() < 3 or args.size() > 4:
		return "Usage: " + command_usage

	var target: CommandTarget.Result = CommandTarget.resolve(args[1], peer_id, server_instance)
	if not target.ok:
		return target.error
	if not target.online:
		return "%s must be online to grant XP." % target.label()

	var amount: int = args[2].to_int()
	if amount == 0:
		return "Invalid XP amount."

	# 4th arg = mastery mode: credit a weapon category instead of the character.
	if args.size() == 4:
		return _grant_mastery(target, amount, StringName(args[3].to_lower()), server_instance)

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


func _grant_mastery(
	target: CommandTarget.Result,
	amount: int,
	category: StringName,
	server_instance: ServerInstance
) -> String:
	if MasteryService.tree_for(category) == null:
		return "No mastery tree for '%s'." % category

	var res: PlayerResource = target.resource
	var mastery: Dictionary = res.add_mastery_xp(category, amount)

	# Same payload shape as a kill so the toast/UI handling comes free
	# (xp = 0 keeps the character-xp line silent).
	server_instance.world_server.data_push.rpc_id(target.peer_id, &"combat.reward", {
		"xp": 0,
		"loot": [],
		"mastery": mastery,
	})

	# Passives/loadout may newly apply if the player wields this category.
	var player: Player = server_instance.players_by_peer_id.get(target.peer_id, null)
	if player != null:
		MasteryService.refresh(player)

	return "Granted %d %s mastery XP to %s (now Lv %d, %d/%d)." % [
		amount, category, target.label(),
		int(mastery.get("level", 1)), int(mastery.get("xp", 0)), int(mastery.get("xp_to_next", 1)),
	]
