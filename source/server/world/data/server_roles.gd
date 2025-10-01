class_name ServerRoles
extends Resource

# Lower the priority, less access to commands it has. 
# Make sure to leave the highest priority (100) to the developer/higher role 
# as it will have access to every command.

@export var roles: Dictionary[String, Dictionary] = {
	"default": {
		"priority": 0,
		"commands": []
	},
	"moderator": {
		"priority": 1,
		"commands": []
	},
	"admin": {
		"priority": 2,
		"commands": []
	},
	"senior_admin": {
		"priority": 100,
		"commands": []
	}
}


func get_roles() -> Dictionary:
	return roles


func create_role() -> void:
	pass


func delete_role() -> void:
	pass