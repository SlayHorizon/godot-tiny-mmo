extends DataRequestHandler


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var skill_name: StringName = StringName(args.get("skill", ""))
	var perk_id: StringName = StringName(args.get("perk", ""))

	# Only mining has perks for now; reject unknown skills/perks.
	if skill_name != MiningPerks.SKILL_NAME or not MiningPerks.PERKS.has(perk_id):
		return {"ok": false}

	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if not player:
		return {"ok": false}

	var skill: Dictionary = player.player_resource.get_skill(skill_name)
	var perks: Dictionary = skill["perks"]

	# Respect the perk's max rank.
	if int(perks.get(perk_id, 0)) >= int(MiningPerks.PERKS[perk_id]["max_rank"]):
		return {"ok": false, "reason": "maxed"}

	# Must have an unspent point.
	if MiningPerks.available_points(skill) <= 0:
		return {"ok": false, "reason": "no_points"}

	perks[perk_id] = int(perks.get(perk_id, 0)) + 1
	return {"ok": true}
