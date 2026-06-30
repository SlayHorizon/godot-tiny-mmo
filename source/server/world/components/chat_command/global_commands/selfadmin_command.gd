extends ChatCommand


func _init():
	command_name = 'selfadmin'
	# Priority ABOVE the highest role (senior_admin = 100) so it is unreachable in
	# any shipped build — a command runs when command_priority <= the caller's role
	# priority, and 101 beats everyone.
	command_priority = 101

	# Dev convenience: enable ONLY inside the Godot editor.
	# SECURITY: this MUST be "editor", never "debug". "debug" is also present in any
	# debug-FEATURED export, so gating on it let every player run /selfadmin (→
	# senior_admin) on a debug server build. "editor" is true only when running from
	# the Godot editor and is ALWAYS false in every export, debug or release.
	if OS.has_feature("editor"):
		command_priority = 0

# Editor-only: grants the caller senior_admin. Unreachable in any export (see _init).
func execute(_args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	server_instance.world_server.connected_players[peer_id].server_roles["senior_admin"] = {}
	return "Yes admin"
