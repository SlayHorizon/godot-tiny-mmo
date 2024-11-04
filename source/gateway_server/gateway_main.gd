extends Node


const GatewayServer = preload("res://source/gateway_server/gateway_server/gateway_server.gd")
const GatewayManager = preload("res://source/gateway_server/gateway_manager/gateway_manager.gd")

@onready var gateway_server: GatewayServer = $GatewayServer
@onready var gateway_manager: GatewayManager = $GatewayManager


func _ready() -> void:
	pass
