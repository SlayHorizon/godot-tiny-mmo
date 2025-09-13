extends DataRequestHandler


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	return instance.players_by_peer_id[peer_id].player_resource.inventory
