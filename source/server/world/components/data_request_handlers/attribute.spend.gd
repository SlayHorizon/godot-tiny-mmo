extends DataRequestHandler


const AttributesMap = preload("res://source/common/gameplay/combat/attributes/attributes_map.gd")


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if not player:
		return {}
	if player.player_resource.available_attributes_points > 0:
		var gained_stats: Dictionary = AttributesMap.attr_to_stats(
			[args["attr"]]
		)
		var value: float
		for stat_name: StringName in gained_stats:
			value = player.ability_system_component.get_value(stat_name)
			value += gained_stats[stat_name]
			player.ability_system_component.set_max_server(
				stat_name,
				value
			)
			player.ability_system_component.set_value_server(
				stat_name,
				value
			)
		player.player_resource.available_attributes_points -= 1
		return {"spent": -1}
	return {}
