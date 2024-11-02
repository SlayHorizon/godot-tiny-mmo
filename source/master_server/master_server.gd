extends Node


# Class Dependencies
const Database: GDScript = preload("res://source/master_server/components/database.gd")
const WorldManager: GDScript = preload("res://source/master_server/components/world_manager.gd")
const GatewayManager: GDScript = preload("res://source/master_server/components/gateway_manager.gd")
const AuthenticationManager: GDScript = preload("res://source/master_server/components/authentication_manager.gd")

# Master Components
var database: Database
var world_manager: WorldManager
var gateway_manager: GatewayManager
var authentication_manager: AuthenticationManager


func _ready() -> void:
	database = Database.new()
	world_manager = WorldManager.new()
	gateway_manager = GatewayManager.new()
	authentication_manager = AuthenticationManager.new()
	
	world_manager.name = "WorldManager"
	gateway_manager.name = "GatewayManager"
	
	world_manager.master = self
	gateway_manager.master = self
	authentication_manager.database = database
	
	deferred.call_deferred()


func deferred() -> void:
	add_sibling(database, true)
	add_sibling(world_manager, true)
	add_sibling(gateway_manager, true)
	add_sibling(authentication_manager, true)
