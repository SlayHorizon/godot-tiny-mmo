class_name GatewayServer
extends Node
## This gateway server is really cheap and minimal,
## consider using different service for commercial project.

const PORT: int = 8088

const GameServerListener = preload("res://source/gateway_server/game_server_listener.gd")

var server: WebSocketMultiplayerPeer

var game_server_listener: GameServerListener
var game_server_1 := {
	"127.0.0.1": 8087
}
var game_server_list := {
	#GameServerListener.new(): {"127.0.0.1": 8087},
}

var connected_peers: Dictionary

# 15 minutes in seconds.
var expiration_time: float = 900.0

var account_collection: AccountResourceCollection
var account_collection_path := "res://source/gateway_server/account_collection.tres"


func _ready() -> void:
	var expiration_timer := Timer.new()
	expiration_timer.autostart = true
	expiration_timer.wait_time = 60.0
	expiration_timer.timeout.connect(self._on_expiration_timer_timeout)
	add_child(expiration_timer)
	if ResourceLoader.exists(account_collection_path):
		account_collection = ResourceLoader.load(account_collection_path)
	else:
		account_collection = AccountResourceCollection.new()
	start_gateway_server()
	game_server_listener = GameServerListener.new()
	game_server_listener.name = "GatewayBridge"
	add_sibling(game_server_listener, true)
	game_server_listener.start_game_server_listener()
	


func _exit_tree() -> void:
	ResourceSaver.save(account_collection, account_collection_path)


func _on_expiration_timer_timeout() -> void:
	for peer_id: int in connected_peers:
		var connection_time: float = Time.get_unix_time_from_system() - connected_peers[peer_id]["time"]
		if connection_time > expiration_time:
			server.disconnect_peer(peer_id)
			connected_peers.erase(peer_id)


func start_gateway_server() -> void:
	print("Start gateway server.")
	server = WebSocketMultiplayerPeer.new()
	
	multiplayer.peer_connected.connect(self._on_peer_connected)
	multiplayer.peer_disconnected.connect(self._on_peer_disconnected)
	
	var server_certificate = load("res://source/common/server_certificate.crt")
	var server_key = load("res://source/game_server/server_key.key")
	if server_certificate == null or server_key == null:
		print("Failed to load certificate or key.")
		return
	
	server.create_server(PORT, "*", TLSOptions.server(server_key, server_certificate))
	multiplayer.set_multiplayer_peer(server)


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
func login_request(username: String, password: String) -> void:
	var peer_id := multiplayer.get_remote_sender_id()
	var result := validate_credentials(username, password)
	if result:
		connected_peers[peer_id] = account_collection[username]
	var message := "Login successful." if result else "Invalid information."
	login_result.rpc_id(peer_id, result, message)


@rpc("authority")
func login_result(_result: bool, _message: String) -> void:
	pass


@rpc("any_peer")
func create_account_request(username: String, password: String, is_guest: bool) -> void:
	var peer_id := multiplayer.get_remote_sender_id()
	var message := ""
	
	if username.is_empty():
		message = "Username cannot be empty."
	elif username.length() < 3:
		message = "Username too short. Minimum 3 characters."
	elif username.length() > 12:
		message = "Username too long. Maximum 12 characters."
	elif username_exists(username):
		message = "Username already exists."
	elif not is_guest:
		if password.is_empty():
			message = "Password cannot be empty."
		elif password.length() < 6:
			message = "Password too short. Minimum 6 characters."
	else:
		message = "Account creation successful."
	
	var is_valid := message == "Account creation successful."
	if is_valid:
		connected_peers[peer_id] = create_accout(username, password, is_guest)
	account_creation_result.rpc_id(peer_id, is_valid, message)


@rpc("authority")
func account_creation_result(_result: bool, _message: String) -> void:
	pass


# Used to create the player's character.
@rpc("any_peer")
func create_player_request(character_class: String) -> void:
	var peer_id := multiplayer.get_remote_sender_id()
	var result := true
	var message := "Character creation successful."
	if not connected_peers.has(peer_id):
		result = false
		message = "Please create an account first."
	if not character_class in ["knight", "rogue", "wizard"]:
		result = false
		message = "Wrong class. Please choose a valid class."
	if not result:
		player_creation_result.rpc_id(peer_id, result, message)
		return
	var player := PlayerResource.new(account_collection.next_player_id)
	player.character_class = character_class
	(connected_peers[peer_id] as AccountResource).player_collection.append(player)
	player_creation_result.rpc_id(peer_id, result, message)
	var random_token := generate_random_token()
	game_server_listener.fetch_token.rpc_id(
		game_server_listener.game_server_list[0],
		random_token,
		{"username": player.display_name,
		"class": player.character_class}
	)
	connect_to_server_request.rpc_id(
		peer_id,
		random_token,
		game_server_1.keys()[0],
		game_server_1.values()[0],
	)

@rpc("authority")
func player_creation_result(_result: bool, _message: String) -> void:
	pass


@rpc("authority")
func connect_to_server_request(_token: String, _adress: String, _port: int) -> void:
	pass


func validate_credentials(username: String, password: String) -> bool:
	if account_collection.collection.has(username):
		if (account_collection.collection[username] as AccountResource).password == password:
			return true
	return false


func username_exists(username: String) -> bool:
	if account_collection.collection.has(username):
		return true
	return false


func create_accout(username: String, password: String, is_guest: bool) -> AccountResource:
	var account_id: int = account_collection.next_account_id
	if is_guest:
		password = generate_random_token()
	var new_account := AccountResource.new(account_id, username, password)
	account_collection.collection[username] = new_account
	return new_account


# Consider using a better token generator.
func generate_random_token() -> String:
	var characters := "abcdefghijklmnopqrstuvwxyz#$-+0123456789"
	var password := ""
	for i in range(12):
		password += characters[randi()% len(characters)]
	return password
