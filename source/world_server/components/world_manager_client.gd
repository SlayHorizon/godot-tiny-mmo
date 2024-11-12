class_name WorldManagerClient
extends BaseClient


signal token_received(token: String, username: String, character_id: int)


@export var world_main: WorldMain
@export var world_server: WorldServer

var world_info: Dictionary


func _ready() -> void:
	await world_main.ready
	load_client_configuration("world-manager-client", "res://test_config/world_server_config.cfg")
	start_client()


func _on_connection_succeeded() -> void:
	print("Succesfuly connected to the Gateway as %d!" % multiplayer.get_unique_id())
	fetch_server_info.rpc_id(
		1,
		{
			"port": world_server.port,
			"adress": "127.0.0.1",
			"info": world_main.world_info,
			"population": world_server.player_list.size()
		}
	)


func _on_connection_failed() -> void:
	print("Failed to connect to the MasterServer as WorldServer.")


func _on_server_disconnected() -> void:
	print("Game Server disconnected.")


@rpc("any_peer")
func fetch_server_info(_info: Dictionary) -> void:
	pass


@rpc("authority")
func fetch_token(token: String, username: String, character_id: int) -> void:
	token_received.emit(token, username, character_id)


@rpc("any_peer")
func player_disconnected(_username: String) -> void:
	pass


@rpc("authority")
func create_player_character_request(gateway_id: int, peer_id: int, username: String, character_data: Dictionary) -> void:
	if world_server.player_list.has(username) and world_server.player_list[username].size()  > 3:
		player_character_creation_result.rpc_id(1, gateway_id, peer_id, username, -1)
		return
	#world_server.characters[username] = {world_server.next_id: character_data}
	#world_server.characters[username][world_server.next_id][character_data]
	world_server.characters[world_server.next_id] = character_data
	if world_server.player_list.has(username):
		world_server.player_list[username].append(world_server.next_id)
	else:
		world_server.player_list[username] = [world_server.next_id]
	player_character_creation_result.rpc_id(1, gateway_id, peer_id, username, world_server.next_id)
	world_server.next_id += 1


@rpc("any_peer")
func player_character_creation_result(_gateway_id: int, _peer_id: int, _username: String, _result_code: int) -> void:
	pass
