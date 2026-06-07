extends ChatCommand
## List players currently in the caller's instance. Scoped to the local instance
## because a world-wide /who would dump hundreds of lines into chat; if/when we
## need a global roster, build it as a dedicated panel.


func _init() -> void:
	command_name = "who"
	command_priority = 1 # moderator+
	command_usage = "/who"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	var lines: PackedStringArray = PackedStringArray()
	for pid: int in server_instance.players_by_peer_id:
		var p: Player = server_instance.players_by_peer_id[pid]
		if p == null or p.player_resource == null:
			continue
		var res: PlayerResource = p.player_resource
		lines.append("- %s @%s (#%d)" % [res.display_name, res.account_name, res.player_id])

	if lines.is_empty():
		return "No players in this instance."

	var instance_name: String = server_instance.instance_resource.instance_name
	return "Players in %s (%d):\n%s" % [instance_name, lines.size(), "\n".join(lines)]
