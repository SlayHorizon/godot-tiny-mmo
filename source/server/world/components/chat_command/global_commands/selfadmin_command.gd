extends ChatCommand


func _init():
	command_name = 'selfadmin'
	# Debug-only convenience. In a release build the priority is set ABOVE the
	# highest role (senior_admin = 100) so it is unreachable — otherwise an admin
	# (priority 2) could use it to escalate themselves to senior_admin (100).
	command_priority = 101

	# For debugging
	if OS.has_feature("debug") or OS.has_feature("editor"):
		command_priority = 0

# Only running in debug mode for now.
func execute(_args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	server_instance.world_server.connected_players[peer_id].server_roles["senior_admin"] = {}
	return "Yes admin"
