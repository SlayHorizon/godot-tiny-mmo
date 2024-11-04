class_name LoginScene
extends Node


var world_server: Node

@onready var login_menu: LoginMenu = $CanvasLayer/LoginMenu
@onready var gateway: Node = $GatewayServer


func _ready() -> void:
	login_menu.gateway = gateway
	gateway.connection_changed.connect(login_menu._on_gateway_connection_changed)
	
	login_menu.connection_succeed.connect(_on_connection_succeed)
	login_menu.gateway.authentication_token_received.connect(_on_authentication_token_received)


func _on_connection_succeed() -> void:
	pass


func _on_authentication_token_received(token: String, adress: String, port: int) -> void:
	world_server.authentication_token = token
	world_server.connect_to_server(adress, port)
	await world_server.connection_changed
	if not world_server.is_connected_to_server:
		printerr("Failed to connect to server after login.")
		return
	add_sibling(preload("res://source/client/ui/ui.tscn").instantiate())
	queue_free.call_deferred()
