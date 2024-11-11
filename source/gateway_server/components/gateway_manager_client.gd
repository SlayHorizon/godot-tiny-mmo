class_name GatewayManagerClient
extends BaseClient


signal account_creation_result_received(user_id: int, result_code: int, data: Dictionary)
signal login_succeeded(account_info: Dictionary)

@export var gateway: GatewayServer

var game_server_list: Dictionary


func _ready() -> void:
	await get_tree().create_timer(1.5).timeout
	load_client_configuration("gateway-manager-client", "res://test_config/gateway_config.cfg")
	start_client()


func _on_connection_succeeded() -> void:
	print("Succesfuly connected to the Gateway Manager as %d!" % multiplayer.get_unique_id())


func _on_connection_failed() -> void:
	print("Failed to connect to the Gateway Manager as Gateway.")


func _on_server_disconnected() -> void:
	print("Gateway Manager disconnected.")


@rpc("authority")
func fetch_authentication_token(target_peer: int, token: String, _adress: String, _port: int) -> void:
	gateway.fetch_authentication_token.rpc_id(target_peer, token, _adress, _port)
	(gateway.connected_peers[target_peer] as Dictionary).erase("account")
	gateway.connected_peers[target_peer]["token_received"] = true


@rpc("any_peer")
func login_request(_peer_id: int, _username: String, _password: String) -> void:
	pass


@rpc("authority")
func login_result(peer_id: int, result: Dictionary) -> void:
	if result.has("error"):
		gateway.login_result.rpc_id(peer_id, result["error"])
	else:
		gateway.login_result.rpc_id(peer_id, 0)
		login_succeeded.emit(peer_id, result)


@rpc("any_peer")
func create_account_request(_peer_id: int, _username: String, _password: String, _is_guest: bool) -> void:
	pass


@rpc("authority")
func account_creation_result(peer_id: int, result_code: int, result: Dictionary) -> void:
	if result_code == OK:
		login_succeeded.emit(peer_id, result)
	gateway.account_creation_result.rpc_id(peer_id, result_code)

@rpc("any_peer")
func create_player_character_request(_peer_id: int , _account_id: int, _character_data: Dictionary, _world_id: int) -> void:
	pass


@rpc("authority")
func player_character_creation_result(peer_id: int, result_code: int) -> void:
	gateway.player_character_creation_result.rpc_id(
		peer_id, result_code
	)
