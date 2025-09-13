extends DataRequestHandler


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if not player:
		return {}
	
	var action_index: int = args.get("i", 0)
	var action_direction: Vector2 = args.get("d", Vector2.ZERO)
	if player.equipped_weapon_right.try_perform_action(action_index, action_direction):
		instance.propagate_rpc(instance.data_push.bind(
			&"action.perform",
			{"i": action_index, "d": action_direction, "p": peer_id}
		))
	return {}
