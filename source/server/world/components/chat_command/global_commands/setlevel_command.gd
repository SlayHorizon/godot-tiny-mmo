extends ChatCommand
## Jump straight to a specific level. Useful for testing high-level quests
## without grinding XP. Sets experience back to 0 within the new level.
## Grants ATTRIBUTE_POINTS_PER_LEVEL per level jumped so the player still has
## something to spend.
##
## Usage:
##   /setlevel 15           # jump self to level 15
##   /setlevel 1 1042       # reset player #1042 to level 1


func _init() -> void:
	command_name = "setlevel"
	command_priority = 100 # senior_admin


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() < 2:
		return "Usage: /setlevel <level> [player_id]"
	var new_level: int = args[1].to_int()
	if new_level < 1 or new_level > 20:
		return "Level must be between 1 and 20."

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
	target.level = new_level
	target.experience = 0
	# Compensate the attribute-point gain that would have happened naturally.
	var levels_jumped: int = new_level - level_before
	if levels_jumped > 0:
		target.available_attributes_points += levels_jumped * PlayerResource.ATTRIBUTE_POINTS_PER_LEVEL

	# Push XP-bar update so the client shows the new level immediately.
	ws.data_push.rpc_id(target_peer_id, &"combat.reward", {
		"xp": 0,
		"level": target.level,
		"levels_gained": maxi(0, levels_jumped),
		"points_gained": maxi(0, levels_jumped * PlayerResource.ATTRIBUTE_POINTS_PER_LEVEL),
		"experience": 0,
		"xp_to_next": target.level_xp_to_next(),
		"loot": [],
	})

	# Fire milestone notifications for any levels crossed upward.
	if levels_jumped > 0:
		var inst: ServerInstance = ws.instance_manager.find_instance_for_peer(target_peer_id)
		LevelMilestoneService.on_levels_gained(target, level_before, new_level, inst)

	return "Set %s to level %d." % [target.display_name, new_level]
