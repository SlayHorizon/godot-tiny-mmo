extends ChatCommand
## Grant experience to a player. Defaults to the caller (you), or supply a
## player_id to grant to someone else (moderation / testing helper). Triggers
## the same level-up + milestone-notification flow as a kill or quest turn-in,
## so it's a clean way to fast-forward through quest gates.
##
## Usage:
##   /xp 1000              # grant 1000 XP to self
##   /xp 250 1042          # grant 250 XP to player #1042


func _init() -> void:
	command_name = "xp"
	command_priority = 100 # senior_admin


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() < 2:
		return "Usage: /xp <amount> [player_id]"
	var amount: int = args[1].to_int()
	if amount == 0:
		return "Invalid XP amount."

	var ws: WorldServer = server_instance.world_server
	var target_peer_id: int = peer_id
	var target: PlayerResource = ws.connected_players.get(peer_id)
	if args.size() >= 3:
		var target_id: int = args[2].to_int()
		target_peer_id = ws.player_id_to_peer_id.get(target_id, 0)
		if target_peer_id == 0:
			return "No online player with id %d." % target_id
		target = ws.connected_players.get(target_peer_id)
	if target == null:
		return "Couldn't find a target player."

	var level_before: int = target.level
	var progress: Dictionary = target.add_experience(amount)

	# Push the same combat.reward payload a kill/quest does so the client gets
	# the XP bar + level-up handling for free.
	ws.data_push.rpc_id(target_peer_id, &"combat.reward", {
		"xp": amount,
		"level": int(progress.get("level", 1)),
		"levels_gained": int(progress.get("levels_gained", 0)),
		"points_gained": int(progress.get("points_gained", 0)),
		"experience": target.experience,
		"xp_to_next": target.level_xp_to_next(),
		"loot": [],
	})

	if int(progress.get("levels_gained", 0)) > 0:
		var inst: ServerInstance = ws.instance_manager.find_instance_for_peer(target_peer_id)
		LevelMilestoneService.on_levels_gained(target, level_before, int(progress.get("level", 1)), inst)

	return "Granted %d XP to %s (now level %d, %d/%d)." % [
		amount, target.display_name, target.level, target.experience, target.level_xp_to_next()
	]
