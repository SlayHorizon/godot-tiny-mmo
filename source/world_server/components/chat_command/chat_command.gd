class_name ChatCommand
extends RefCounted


@warning_ignore("unused_parameter")
func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> bool:
	return false


@warning_ignore("unused_parameter")
func is_admin(peer_id: int, server_instance: ServerInstance) -> bool:
	var character_id: int = server_instance.world_server.connected_players[peer_id].player_id
	return server_instance.world_server.database.player_data.admin_ids.has(character_id)
