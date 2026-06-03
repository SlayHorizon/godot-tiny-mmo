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
	# Iterate the JobRegistry instead of the player's skills dict directly,
	# so the Jobs UI can show ALL trainable professions (even ones the
	# player has 0 XP in) rather than only the ones they've already gathered
	# from. Unstarted jobs render as "Lv 1 — 0 xp" with no perk choices.
	for skill_name in JobRegistry.JOBS:
		var jp: JobPerks = JobRegistry.JOBS[skill_name]
		var entry: Dictionary = resource.skills.get(skill_name, {})
		var skill_level: int = int(entry.get("level", 1))
		var info: Dictionary = {
			"level": skill_level,
			"xp": int(entry.get("xp", 0)),
			"xp_to_next": resource.skill_xp_to_next(skill_level),
			"display_name": jp.display_name if not jp.display_name.is_empty() else String(skill_name).capitalize(),
			"category": String(jp.category),
			"order": jp.sort_order,
		}

		# Perk picker payload — generic across all jobs via the JobPerks
		# resource. UI reads info["choices"] for the picker and info["perks"]
		# for the effective-bonuses lines.
		if jp != null:
			var perks_dict: Dictionary = entry.get("perks", {})
			info["perks"] = jp.describe(skill_level, perks_dict)
			info["points"] = jp.available_points({"level": skill_level, "perks": perks_dict})
			# Sources / Recipes tabs read JobRegistry directly on the client
			# (JobPerks is preloaded in `common/`, so the client already has
			# the rich Item refs + required-levels). No need to ship them.
			var choices: Array = []
			for perk in jp.perks:
				var pid: StringName = StringName(String(perk.get("id", "")))
				# Ship effect + per_rank too so the Jobs UI can render an
				# inline "what one rank gives" description without needing
				# its own copy of the perk effect vocabulary.
				choices.append({
					"id": String(pid),
					"name": String(perk.get("name", "")),
					"effect": String(perk.get("effect", "")),
					"per_rank": float(perk.get("per_rank", 0.0)),
					"rank": int(perks_dict.get(pid, 0)),
					"max_rank": int(perk.get("max_rank", 0)),
				})
			info["choices"] = choices

		out[String(skill_name)] = info
	return {"skills": out}
