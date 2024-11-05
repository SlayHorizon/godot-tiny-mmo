extends BaseServer


const GatewayManager = preload("res://source/gateway_server/gateway_manager/gateway_manager.gd")

var connected_peers: Dictionary

@onready var gateway_manager: GatewayManager = $"../GatewayManager"


func _ready() -> void:
	gateway_manager.account_creation_result_received.connect(
		func(peer_id: int, result_code: int, data: Dictionary):
			connected_peers[peer_id]["account"] = data
			account_creation_result.rpc_id(peer_id, result_code)
	)
	load_server_configuration("gateway-server", "res://test_config/gateway_config.cfg")
	start_server()


func _on_peer_connected(peer_id: int) -> void:
	print("Peer: %d is connected." % peer_id)
	connected_peers[peer_id] = {"time" = Time.get_unix_time_from_system()}


func _on_peer_disconnected(peer_id: int) -> void:
	connected_peers.erase(peer_id)
	print("Peer: %d is disconnected." % peer_id)


@rpc("authority")
func fetch_authentication_token(_token: String, _adress: String, _port: int) -> void:
	pass


@rpc("any_peer")
func login_request(_username: String, _password: String) -> void:
	pass
	#var peer_id := multiplayer.get_remote_sender_id()
	#var result := validate_credentials(username, password)
	#if result:
		#connected_peers[peer_id]["account"] = account_collection[username]
	#var message := "Login successful." if result else "Invalid information."
	#login_result.rpc_id(peer_id, result, message)


@rpc("authority")
func login_result(_result: bool, _message: String) -> void:
	pass


@rpc("any_peer")
func create_account_request(username: String, password: String, is_guest: bool) -> void:
	var peer_id := multiplayer.get_remote_sender_id()
	if is_guest:
		gateway_manager.create_account_request.rpc_id(1, peer_id, username, password, is_guest)
		return
	var result_code: int = 0
	if username.is_empty():
		result_code = 1
	elif username.length() < 3:
		result_code = 2
	elif username.length() > 12:
		result_code = 3
	elif password.is_empty():
		result_code = 4
	elif password.length() < 6:
		result_code = 5
	elif password.length() > 30:
		result_code = 6
	
	if result_code == OK:
		gateway_manager.create_account_request.rpc_id(1, peer_id, username, password, is_guest)
	else:
		account_creation_result.rpc_id(peer_id, result_code)


@rpc("authority")
func account_creation_result(_result_code: int) -> void:
	pass


@rpc("any_peer")
func create_player_character_request(character_data: Dictionary, world_id: int) -> void:
	var peer_id := multiplayer.get_remote_sender_id()
	var result_code: int = 0
	var character_name := ""
	if not character_data.has_all(["name", "class"]):
		result_code = 9
	else:
		character_name = character_data["name"]
	if not connected_peers[peer_id].has("account"):
		result_code = 7
	elif not character_data["class"] in ["knight", "rogue", "wizard"]:
		result_code = 8
	elif character_name.is_empty():
		result_code = 1
	elif character_name.length() < 3:
		result_code = 2
	elif character_name.length() > 12:
		result_code = 3

	if result_code != OK:
		player_character_creation_result.rpc_id(peer_id, result_code)
	else:
		gateway_manager.create_player_character_request.rpc_id(
			1,
			world_id,
			peer_id,
			connected_peers[peer_id]["account"]["id"],
			character_data,
		)


@rpc("authority")
func player_character_creation_result(_result_code: int) -> void:
	pass
