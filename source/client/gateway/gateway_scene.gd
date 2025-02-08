class_name LoginScene
extends Node


@export var world_server: WorldClient
@export var gateway_ui: GatewayUI
@export var gateway: GatewayClient


func _ready() -> void:
	gateway.authentication_token_received.connect(_on_authentication_token_received)
	
	gateway.login_succeeded.connect(gateway_ui.on_login_succeeded)
	gateway.connection_changed.connect(gateway_ui._on_gateway_connection_changed)


func _on_authentication_token_received(auth_token: String, address: String, port: int) -> void:
	world_server.authentication_token = auth_token
	world_server.connect_to_server(address, port)
	await world_server.connection_changed
	if not world_server.is_connected_to_server:
		printerr("Failed to connect to server after login.")
		return
	add_sibling(preload("res://source/client/ui/ui.tscn").instantiate())
	queue_free.call_deferred()
