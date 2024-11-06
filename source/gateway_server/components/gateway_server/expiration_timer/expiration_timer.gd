extends Timer


# 15 minutes in seconds by default.
@export var expiration_time: float = 900.0

@export var gateway_server: GatewayServer


func _ready() -> void:
	pass


func _on_expiration_timer_timeout() -> void:
	for peer_id: int in gateway_server.connected_peers:
		if gateway_server.connected_peers.has("account"):
			return
		var connection_time: float = Time.get_unix_time_from_system() - gateway_server.connected_peers[peer_id]["time"]
		if connection_time > expiration_time:
			gateway_server.server.disconnect_peer(peer_id)
			gateway_server.connected_peers.erase(peer_id)
