extends Node
class_name BaseMultiplayerEndpoint

## horizon: feel free to edit if needed
## Minimal, reusable multiplayer bootstrap.
## Override `_connect_multiplayer_api_signals()` in subclasses to wire only what you need.

enum Role {
	CLIENT,
	SERVER
}

var peer: WebSocketMultiplayerPeer #extends MultiplayerPeer
var multiplayer_api: SceneMultiplayer #extends MultiplayerAPI


# Uncomment if you want to do your own polling, otherwise SceneTree takes care of it.
#func _process(_delta: float) -> void:
	#if multiplayer_api and multiplayer_api.has_multiplayer_peer():
		#multiplayer_api.poll()


## Should be called once
func init_multiplayer(use_root_api: bool = false) -> void:
	multiplayer_api = (
		MultiplayerAPI.create_default_interface()
		if not use_root_api else multiplayer
	)
	
	# MMO choice, no peer gossip via server
	multiplayer_api.server_relay = false
	
	# Setup signals, has to be ovverride by subclass.
	_connect_multiplayer_api_signals(multiplayer_api)
	
	# Set to a custom path, else use root path.
	get_tree().set_multiplayer(
		multiplayer_api,
		NodePath("") if use_root_api else get_path()
	)

	# Create the kind of peer we want.
	peer = WebSocketMultiplayerPeer.new()

	if peer.is_server_relay_supported(): # Necessary check ?
		# We want to disable the server feature that can notifies clients of other peers' connection/disconnection,
		# and relays messages between them.
		multiplayer_api.server_relay = false


## Override this in subclasses to connect native SceneMultiplayer signals.
func _connect_multiplayer_api_signals(api: SceneMultiplayer) -> void:
	pass


## Create as client or server.
## TLS usefull for wss (WebSocket Secure) unless you have anything else taking care of it like Caddy.
func create(role: Role, address: String, port: int, tls_options: TLSOptions = null) -> Error:
	if not multiplayer_api:
		init_multiplayer();

	var error: Error

	match role:
		Role.CLIENT:
			# `address` may be either:
			#   (a) a bare host like "127.0.0.1" — build a URL from scheme + port
			#   (b) a full URL like "wss://ws.example.com/world/1" — use as-is
			# (b) is what production deploys behind a reverse proxy (Caddy/nginx)
			# send, because the path discriminates which world and the port is
			# part of the proxy's public binding.
			var url: String
			if address.contains("://"):
				url = address
			else:
				var scheme: String = "ws" if tls_options == null or tls_options.is_unsafe_client() else "wss"
				url = "%s://%s:%d" % [scheme, address, port]
			error = peer.create_client(url, tls_options)
		Role.SERVER:
			var bind_address: String = "*" if address.is_empty() else address
			error = peer.create_server(port, bind_address, tls_options)
		_:
			return Error.FAILED

	if error != OK:
		printerr("Error while creating peer: %s" % error_string(error))
		return error

	# Setting this, calls SceneMultiplayer::set_multiplayer_peer
	# which check "p_peer.is_valid() && p_peer->get_connection_status() == MultiplayerPeer::CONNECTION_DISCONNECTED"
	# Meaning the supplied peer must be either connecting or connected I guess
	multiplayer_api.multiplayer_peer = peer

	return Error.OK
