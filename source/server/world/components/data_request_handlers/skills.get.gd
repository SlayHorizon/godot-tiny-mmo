extends DataRequestHandler


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if not player:
		return {}

	var resource: PlayerResource = player.player_resource
	var out: Dictionary = {}
	for skill_name in resource.skills:
		var entry: Dictionary = resource.skills[skill_name]
		var skill_level: int = int(entry.get("level", 1))
		var info: Dictionary = {
			"level": skill_level,
			"xp": int(entry.get("xp", 0)),
			"xp_to_next": resource.skill_xp_to_next(skill_level),
		}
		# Per-profession perks (only mining has them for now): effective summary lines,
		# spendable points, and the choosable perk list for the picker.
		if StringName(skill_name) == MiningPerks.SKILL_NAME:
			var skill_perks: Dictionary = entry.get("perks", {})
			info["perks"] = MiningPerks.describe(skill_level, skill_perks)
			info["points"] = MiningPerks.available_points(entry)
			var choices: Array = []
			for perk_id in MiningPerks.PERKS:
				var perk_def: Dictionary = MiningPerks.PERKS[perk_id]
				choices.append({
					"id": String(perk_id),
					"name": perk_def["name"],
					"rank": int(skill_perks.get(perk_id, 0)),
					"max_rank": int(perk_def["max_rank"]),
				})
			info["choices"] = choices
		out[String(skill_name)] = info
	return {"skills": out}
