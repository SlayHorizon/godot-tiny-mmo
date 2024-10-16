extends Timer


const GatewayServer = preload("res://source/gateway_server/gateway_server.gd")

# 15 minutes in seconds by default.
@export var expiration_time: float = 900.0

var gateway: GatewayServer


func _ready() -> void:
	pass


func _on_expiration_timer_timeout() -> void:
	for peer_id: int in gateway.connected_peers:
		if gateway.connected_peers.has("account"):
			return
		var connection_time: float = Time.get_unix_time_from_system() - gateway.connected_peers[peer_id]["time"]
		if connection_time > expiration_time:
			gateway.gateway_serer.disconnect_peer(peer_id)
			gateway.connected_peers.erase(peer_id)
