extends DataRequestHandler


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if not player or not player.player_resource:
		return {}
	
	var player_resource: PlayerResource = player.player_resource
	
	var xp_required: int = XPCalculator.get_xp_required_for_level(player_resource.level + 1)
	
	return {
		"experience": player_resource.experience,
		"level": player_resource.level,
		"xp_required": xp_required,
		"total_experience": player_resource.total_experience
	}

