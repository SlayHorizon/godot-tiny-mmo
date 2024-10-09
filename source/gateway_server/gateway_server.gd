class_name GatewayServer
extends Node
## This gateway server is really cheap and minimal,
## consider using different service for commercial project.


const PORT: int = 8088

var server: WebSocketMultiplayerPeer
var connected_peers: Dictionary

# 15 minutes in seconds.
var expiration_time: float = 900.0

var credentials: CredentialsCollectionResource
var credentials_path := "res://source/gateway_server/credentials.tres"


func _ready() -> void:
	var expiration_timer := Timer.new()
	expiration_timer.autostart = true
	expiration_timer.wait_time = 60.0
	expiration_timer.timeout.connect(self._on_expiration_timer_timeout)
	add_child(expiration_timer)
	CredentialsResource.new(0, "salade", "tomate")
	if ResourceLoader.exists(credentials_path):
		credentials = ResourceLoader.load(credentials_path)
	else:
		credentials = CredentialsCollectionResource.new()
	start_gateway_server()


func _exit_tree() -> void:
	ResourceSaver.save(credentials, credentials_path)


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
	print("Peer: %d is disconnected." % peer_id)


@rpc("any_peer")
func login_request(username: String, password: String) -> void:
	var peer_id := multiplayer.get_remote_sender_id()
	var result := validate_credentials(username, password)
	var message := "Login successful" if result else "Invalid credentials"
	login_result.rpc_id(peer_id, result, message)


@rpc("authority")
func login_result(_result: bool, _message: String = "") -> void:
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
	
	var is_valid := message == "Account creation successful"
	account_creation_result.rpc_id(peer_id, is_valid, message)


@rpc("authority")
func account_creation_result(_result: bool, _message: String = "") -> void:
	pass


func validate_credentials(username: String, password: String) -> bool:
	if credentials.collection.has(username):
		if (credentials.collection[username] as CredentialsResource)\
		.password == password:
			return true
	return false


func username_exists(username: String) -> bool:
	if credentials.collection.has(username):
		return true
	return false


func create_accout(username: String, password: String, is_guest: bool) -> void:
	var account_id: int = credentials.next_id
	credentials.next_id += 1
	if is_guest:
		password = generate_password()
	var new_account := CredentialsResource.new(account_id, username, password)
	credentials.collection[username] = new_account


# Consider using a better token generator.
func generate_password() -> String:
	var characters := "abcdefghijklmnopqrstuvwxyz#$-+0123456789"
	var password := ""
	for i in range(12):
		password += characters[randi()% len(characters)]
	return password
