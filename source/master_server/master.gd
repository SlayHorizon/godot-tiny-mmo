extends Node


# Class Dependencies
const Database: GDScript = preload("res://source/master_server/components/database.gd")
const WorldManager = preload("res://source/master_server/components/world_manager/world_manager.gd")
const GatewayManager = preload("res://source/master_server/components/gateway_manager/gateway_manager.gd")
const AuthenticationManager = preload("res://source/master_server/components/authentication_manager/authentication_manager.gd")

# Master Components
@onready var database: Database = $Database
@onready var world_manager: WorldManager = $WorldManager
@onready var gateway_manager: GatewayManager = $GatewayManager
@onready var authentication_manager: AuthenticationManager = $AuthenticationManager


func _ready() -> void:
	world_manager.master = self
	gateway_manager.master = self
	authentication_manager.database = database
