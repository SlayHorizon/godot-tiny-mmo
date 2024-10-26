extends Node


# Loading classes 
const Database: Script = preload("res://source/master_server/database.gd")
const WorldManager: Script = preload("res://source/master_server/world_manager.gd")
const GatewayManager: Script = preload("res://source/master_server/gateway_manager.gd")
const AuthenticationManager: Script = preload("res://source/master_server/authentication_manager.gd")

# References
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
