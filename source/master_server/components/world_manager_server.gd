class_name WorldManagerServer
extends BaseServer


@export var authentication_manager: AuthenticationManager
@export var gateway_manager: GatewayManagerServer

# Active Connections
var next_world_id: int = 0
var connected_worlds: Dictionary

func _ready() -> void:
	load_server_configuration("world-manager-server", "res://test_config/master_server_config.cfg")
	start_server()


func _on_peer_connected(peer_id: int) -> void:
	print("Gateway: %d is connected to GatewayManager." % peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	print("Gateway: %d is disconnected to GatewayManager." % peer_id)


@rpc("any_peer")
func fetch_server_info(info: Dictionary) -> void:
	var game_server_id := multiplayer_api.get_remote_sender_id()
	connected_worlds[game_server_id] = info
	gateway_manager.update_worlds_info.rpc(connected_worlds)


@rpc("authority")
func fetch_token(_token: String, _account_id: int) -> void:
	pass


@rpc("authority")
func create_player_character_request(_gateway_id: int, _peer_id: int, _account_id: int, _character_data: Dictionary) -> void:
	pass


@rpc("any_peer")
func player_character_creation_result(gateway_id: int, peer_id: int, account_id: int, result_code: int) -> void:
	var world_id := multiplayer_api.get_remote_sender_id()
	if result_code == OK:
		var token := authentication_manager.generate_random_token()
		fetch_token.rpc_id(world_id, token, account_id)
		gateway_manager.player_character_creation_result.rpc_id(
			gateway_id, peer_id, result_code
		)
		await get_tree().create_timer(0.5).timeout
		gateway_manager.fetch_authentication_token.rpc_id(
			gateway_id, peer_id, token, "127.0.0.1", 8087
		)
	else:
		gateway_manager.player_character_creation_result.rpc_id(
			gateway_id, peer_id, result_code
		)
