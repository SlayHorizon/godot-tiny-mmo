# Feel free to refactor this
extends Node
## This gateway server is really cheap and minimal,
## consider using different service for commercial project.
## Role of the gateway
## 1. Public-Facing Layer (Security)
## The Gateway serves as a public-facing layer,
## acting as a shield for the more sensitive servers (Auth Server, Main Server).
## It can handle rate limiting, basic request filtering,
## DDoS protection, and ensure that only valid requests reach the Auth Server.
## 2. Basic Validation:
## The Gateway can perform basic request validation, like checking if required parameters are present,
## before forwarding requests to other servers.
## 3. Centralized Entry Point
## For example, if you plan to offer multiple game services or features in the future,
## the Gateway can route requests to the appropriate service without the client needing to know the full architecture.

# Loading classes 
const MasterClient = preload("res://source/gateway_server/master_client.gd")
const ExpirationTimer = preload("res://source/gateway_server/expiration_timer/expiration_timer.gd")

# Default port;
# can be changed via cmdline arg by doing --port=8088
var port: int = 8088

# References
var master_client: MasterClient
var gateway_serer: WebSocketMultiplayerPeer

var connected_peers: Dictionary

@onready var expiration_timer: ExpirationTimer = $ExpirationTimer


func _ready() -> void:
	expiration_timer.gateway = self
	master_client = MasterClient.new()
	master_client.name = "GatewayManager"
	master_client.account_creation_result_received.connect(
		func(peer_id: int, result_code: int, data: Dictionary):
			connected_peers[peer_id]["account"] = data
			account_creation_result.rpc_id(peer_id, result_code)
	)
	master_client.gateway = self
	add_sibling(master_client, true)
	start_gateway_server()


func start_gateway_server() -> void:
	print("Start gateway server.")
	gateway_serer = WebSocketMultiplayerPeer.new()
	
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	
	var server_certificate = load("res://source/common/server_certificate.crt")
	var server_key = load("res://source/game_server/server_key.key")
	if server_certificate == null or server_key == null:
		print("Failed to load certificate or key.")
		return
	
	var error := gateway_serer.create_server(port, "*", TLSOptions.server(server_key, server_certificate))
	if error:
		print(error_string(error))
		return
	multiplayer.set_multiplayer_peer(gateway_serer)


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
		master_client.create_account_request.rpc_id(1, peer_id, username, password, is_guest)
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
		master_client.create_account_request.rpc_id(1, peer_id, username, password, is_guest)
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
		master_client.create_player_character_request.rpc_id(
			1,
			world_id,
			peer_id,
			connected_peers[peer_id]["account"]["id"],
			character_data,
		)


@rpc("authority")
func player_character_creation_result(_result_code: int) -> void:
	pass


func check_for_config() -> void:
	var parsed_arguments := CmdlineUtils.get_parsed_args()
	print("gateway parsed arguments = ", parsed_arguments)
	if parsed_arguments.has("port"):
		port = parsed_arguments[port]

#
#func is_valid_username(username: String) -> bool:
	#if username.is_empty():
		#message = "Username cannot be empty."
	#elif username.length() < 3:
		#message = "Username too short. Minimum 3 characters."
	#elif username.length() > 12:
		#message = "Username too long. Maximum 12 characters."
