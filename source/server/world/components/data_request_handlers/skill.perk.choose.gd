extends DataRequestHandler


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var skill_name: StringName = StringName(args.get("skill", ""))
	var perk_id: StringName = StringName(args.get("perk", ""))

	# Validate via the registry — JobPerks.perks is the source of truth.
	var jp: JobPerks = JobRegistry.perks_for(skill_name)
	if jp == null or not jp.has_perk(perk_id):
		return {"ok": false}

	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if not player:
		return {"ok": false}

	var skill: Dictionary = player.player_resource.get_skill(skill_name)
	var perks: Dictionary = skill["perks"]

	# Per-perk max rank cap.
	var perk_def: Dictionary = jp.get_perk_def(perk_id)
	if int(perks.get(perk_id, 0)) >= int(perk_def.get("max_rank", 0)):
		return {"ok": false, "reason": "maxed"}

	# Available perk-point gate. Same point-pool accounting for every job.
	if jp.available_points(skill) <= 0:
		return {"ok": false, "reason": "no_points"}

	perks[perk_id] = int(perks.get(perk_id, 0)) + 1
	return {"ok": true}
