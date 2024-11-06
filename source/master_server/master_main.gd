extends Node


# Class Dependencies
const Database: GDScript = preload("res://source/master_server/components/database.gd")
const AuthenticationManager = preload("res://source/master_server/components/authentication_manager/authentication_manager.gd")

# Master Components
@onready var database: Database = $Database
@onready var world_manager: WorldManagerServer = $WorldManagerServer
@onready var gateway_manager: GatewayManagerServer = $GatewayManagerServer
@onready var authentication_manager: AuthenticationManager = $AuthenticationManager


func _ready() -> void:
	world_manager.master = self
	gateway_manager.master = self
	authentication_manager.database = database
