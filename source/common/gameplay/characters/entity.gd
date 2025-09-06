class_name Entity
extends CharacterBody2D
## @deprecated
## TO DELETE OR REWORK !!!
##
## Base class for all entities to synchronize among the network,
## can be a player, a NPC or an object like a projectile or a breakable jar.


var team: Team

## Used when initializating the entity.
## Useful to avoid overloading sync_state.
#var spawn_state: Dictionary = {}:
	#set = _set_spawn_state

## Updated and synchronize at each frame,
## try to keep it as small as possible.
#var sync_state: Dictionary = {}:
	#set = _set_sync_state

## If true, keeps processing sync_state,
## else, sync_state won't be synchronized and updated each frame.
#var to_sync: bool = true


#func _set_spawn_state(new_state: Dictionary) -> void:
	#spawn_state = new_state
#
#
#func _set_sync_state(new_state: Dictionary) -> void:
	#sync_state = new_state
	#for property: String in new_state:
		#set(property, new_state[property])
