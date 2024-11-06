class_name GatewayManagerClient
extends BaseClient


signal account_creation_result_received(user_id: int, result_code: int, data: Dictionary)

var game_server_list: Dictionary

@onready var gateway: GatewayServer = $"../GatewayServer"


func _ready() -> void:
	await get_tree().create_timer(1.5).timeout
	load_client_configuration("master-client", "res://test_config/gateway_config.cfg")
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


@rpc("any_peer")
func create_account_request(_peer_id: int, _username: String, _password: String, _is_guest: bool) -> void:
	pass


@rpc("authority")
func account_creation_result(peer_id: int, result_code: int, data: Dictionary) -> void:
	account_creation_result_received.emit(peer_id, result_code, data)


@rpc("any_peer")
func create_player_character_request(_peer_id: int , _account_id: int, _character_data: Dictionary, _world_id: int) -> void:
	pass


@rpc("authority")
func player_character_creation_result(peer_id: int, result_code: int) -> void:
	gateway.player_character_creation_result.rpc_id(
		peer_id, result_code
	)
