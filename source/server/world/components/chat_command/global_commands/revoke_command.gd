extends ChatCommand
## Remove a persisted server role from an online player and save the change.
## Note: roles granted via the admin config file are live and cannot be revoked
## here — remove the account from server_admins.cfg instead.


func _init() -> void:
	command_name = "revoke"
	command_priority = 100 # senior_admin


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() != 3:
		return "Invalid command format: /revoke <player_id> <role>"

	var role: String = args[2]

	# Target by the permanent, unique player_id (display names aren't unique).
	var target_id: int = args[1].to_int()
	var target: PlayerResource = _find_online_player(target_id, server_instance)
	if target == null:
		return "No online player with id %d." % target_id

	if not target.server_roles.has(role):
		return "%s (#%d) does not have the role '%s'." % [target.display_name, target.player_id, role]

	target.server_roles.erase(role)
	server_instance.world_server.database.save_player(target)
	return "Revoked role '%s' from %s (#%d)." % [role, target.display_name, target.player_id]


func _find_online_player(player_id: int, server_instance: ServerInstance) -> PlayerResource:
	var ws: WorldServer = server_instance.world_server
	var target_peer_id: int = ws.player_id_to_peer_id.get(player_id, 0)
	return ws.connected_players.get(target_peer_id) if target_peer_id != 0 else null
