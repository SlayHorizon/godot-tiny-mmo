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
	return {
		"level": resource.level,
		"experience": resource.experience,
		"xp_to_next": resource.level_xp_to_next(),
		"available_points": resource.available_attributes_points,
	}
