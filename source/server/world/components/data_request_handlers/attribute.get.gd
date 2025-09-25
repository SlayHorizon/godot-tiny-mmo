extends DataRequestHandler


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if not player:
		return {}
	return {
		"points": player.player_resource.available_attributes_points,
		"attr": player.player_resource.attributes
	}
