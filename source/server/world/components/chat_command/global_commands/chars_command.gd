extends ChatCommand
## List every character on an account, with display name + character id, so staff
## can target an OFFLINE player by #id (mute / jail / etc.) when they can't open
## the player's profile. Online players are easy to find via /who; this also
## covers offline accounts. A leading @ on the account is optional.


func _init() -> void:
	command_name = "chars"
	command_priority = 1 # moderator+
	command_usage = "/chars <account>"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() != 2:
		return "Usage: " + command_usage

	var account: String = args[1].strip_edges().trim_prefix("@").to_lower()
	if account.is_empty():
		return "Usage: " + command_usage

	var ws: WorldServer = server_instance.world_server
	var characters: Dictionary = ws.database.store.get_account_characters(account)
	if characters.is_empty():
		return "No characters found for account '@%s'." % account

	var lines: PackedStringArray = PackedStringArray()
	for pid: int in characters:
		var info: Dictionary = characters[pid]
		var online: bool = ws.player_id_to_peer_id.get(pid, 0) != 0
		lines.append("- %s (#%d)  Lv %d%s" % [
			str(info.get("name", "?")), pid, int(info.get("level", 1)),
			"  ● online" if online else "",
		])

	return "Characters on @%s (%d):\n%s" % [account, lines.size(), "\n".join(lines)]
