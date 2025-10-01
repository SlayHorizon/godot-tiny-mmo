class_name ChatCommand
extends RefCounted


var command_name: String = ""
var command_alias: PackedStringArray = []
var command_priority: int = 0


@warning_ignore("unused_parameter")
func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	return "Unknown command."
