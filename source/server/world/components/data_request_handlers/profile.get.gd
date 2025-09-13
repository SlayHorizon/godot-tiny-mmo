extends DataRequestHandler


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var to_get: int = args.get("q", 0)
	if not to_get:
		return {}
	var target_player: Player = instance.players_by_peer_id.get(to_get, null)
	if not target_player:
		return {}
	var player_resource: PlayerResource = target_player.player_resource
	var profile: Dictionary = {
		"name": player_resource.display_name,
		"stats": {
			"money": player_resource.golds,
			"character_class": player_resource.character_class,
			"level": player_resource.level
		}
	}
	return profile
