class_name ChatCommand
extends RefCounted


# Not used yet.
var name: String
var aliases: PackedStringArray = []
var description: String = ""


@warning_ignore("unused_parameter")
func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	return "Unknown command."
