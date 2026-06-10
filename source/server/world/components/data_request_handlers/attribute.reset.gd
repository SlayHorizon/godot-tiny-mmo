extends DataRequestHandler
## Re-spec: refunds ALL spent attribute points (clearing the build) for a gold
## fee, so a player can rebuild differently. It's the inverse of attribute.spend
## applied over the whole attributes dict. Cost is AttributeResetInteraction.COST
## (single source of truth, shared with the dialogue that shows the price).


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if not player:
		return {"ok": false}

	var pr: PlayerResource = player.player_resource

	# Total refundable points. Nothing spent → nothing to do (don't charge a no-op).
	var refunded: int = 0
	for attr: StringName in pr.attributes:
		refunded += int(pr.attributes[attr])
	if refunded <= 0:
		return {"ok": false, "reason": "nothing"}

	# Charge the fee — checks + removes atomically (false = can't afford, nothing removed).
	var gold_id: int = Economy.gold_id()
	if gold_id <= 0 or not Inventory.remove_amount_by_id(pr.inventory, gold_id, AttributeResetInteraction.COST):
		return {"ok": false, "reason": "gold"}

	# Remove, live, the stats those points granted (the inverse of attribute.spend).
	var total_stats: Dictionary = AttributeMap.attr_to_stats(pr.attributes)
	for stat_name: StringName in total_stats:
		player.stats_component.modify_stat(stat_name, -total_stats[stat_name])

	# Clamp current HP if the new max dropped (removing Vitality shouldn't leave
	# the player sitting above their max until the next hit).
	var hp_max: float = player.stats_component.get_stat(Stat.HEALTH_MAX)
	var hp: float = player.stats_component.get_stat(Stat.HEALTH)
	if hp > hp_max:
		player.stats_component.modify_stat(Stat.HEALTH, hp_max - hp)

	# Reset the build + hand the points back to spend.
	pr.attributes.clear()
	pr.available_attributes_points += refunded

	return {"ok": true, "points": pr.available_attributes_points, "refunded": refunded}
