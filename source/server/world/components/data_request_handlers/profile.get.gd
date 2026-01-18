extends DataRequestHandler


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	
	var target_id: int = args.get("id", 0)
	if target_id == 0:
		target_id = peer_id
	var target_player: Player = instance.players_by_peer_id.get(target_id, null)
	if not target_player:
		return {}
	var player_resource: PlayerResource = target_player.player_resource
	var profile: Dictionary = {
		"name": player_resource.display_name,
		"skin_id": player_resource.skin_id,
		"stats": {
			"money": player_resource.golds,
			"character_class": "???",
			"level": player_resource.level
		},
		"animation": player_resource.profile_animation,
		"description": player_resource.profile_status,
		"self": true if target_id  == peer_id else false
	}
	return profile
