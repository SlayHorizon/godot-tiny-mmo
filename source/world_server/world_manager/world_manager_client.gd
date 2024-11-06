class_name WorldManagerClient
extends BaseClient


signal token_received(token: String, player_data: Dictionary)

# References
var world_server: WorldServer

var game_server_list: Dictionary


func _ready() -> void:
	load_client_configuration("world-manager-client", "res://test_config/world_server_config.cfg")
	start_client()


func _on_connection_succeeded() -> void:
	print("Succesfuly connected to the Gateway as %d!" % multiplayer.get_unique_id())
	fetch_server_info.rpc_id(
		1,
		{
			"port": world_server.port,
			"adress": "127.0.0.1",
			"rules": "None",
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
func fetch_token(token: String, account_id: int) -> void:
	token_received.emit(token, account_id)


@rpc("authority")
func create_player_character_request(gateway_id: int, peer_id: int, account_id: int, character_data: Dictionary) -> void:
	if world_server.characters.has(account_id) and world_server.characters[account_id].size()  > 3: #max character per account
		player_character_creation_result.rpc_id(1, gateway_id, peer_id, account_id, 22)
		return
	world_server.characters[account_id] = {world_server.next_id: character_data}
	world_server.next_id += 1
	player_character_creation_result.rpc_id(1, gateway_id, peer_id, account_id, 0)


@rpc("any_peer")
func player_character_creation_result(_gateway_id: int, _peer_id: int, _account_id: int, _result_code: int) -> void:
	pass
