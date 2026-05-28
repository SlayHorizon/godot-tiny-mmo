extends ChatCommand
## Grant a server role to an online player and persist it to the database.
## Use this for staff (moderator/admin). The owner should grant themselves
## senior_admin via the admin config file, not here.


func _init() -> void:
	command_name = "grant"
	command_priority = 100 # senior_admin


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() != 3:
		return "Invalid command format: /grant <player_id> <role>"

	var role: String = args[2]
	if not server_instance.global_role_definitions.has(role):
		return "Unknown role '%s'. Known roles: %s" % [
			role, ", ".join(server_instance.global_role_definitions.keys())
		]

	# Target by the permanent, unique player_id (read it from the player's profile,
	# visible to staff). Display names aren't unique, so they can't be used here.
	var target_id: int = args[1].to_int()
	var target: PlayerResource = _find_online_player(target_id, server_instance)
	if target == null:
		return "No online player with id %d." % target_id

	target.server_roles[role] = {}
	server_instance.world_server.database.save_player(target)
	return "Granted role '%s' to %s (#%d)." % [role, target.display_name, target.player_id]


func _find_online_player(player_id: int, server_instance: ServerInstance) -> PlayerResource:
	var ws: WorldServer = server_instance.world_server
	var target_peer_id: int = ws.player_id_to_peer_id.get(player_id, 0)
	return ws.connected_players.get(target_peer_id) if target_peer_id != 0 else null
