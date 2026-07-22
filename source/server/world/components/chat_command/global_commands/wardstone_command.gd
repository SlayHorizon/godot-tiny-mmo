extends ChatCommand
## GM tool for the wardstone progression chain (docs/wardstones.md): grant or
## revoke a stone on a character, or list what they hold — for testing sealed
## portals and unsticking a character without replaying a chain.


func _init() -> void:
	command_name = "wardstone"
	command_priority = 100 # senior_admin
	command_usage = "/wardstone <self|@account|#id> <list|grant|revoke> [slug, e.g. woodland]"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() < 3:
		return "Usage: " + command_usage

	var target: CommandTarget.Result = CommandTarget.resolve(args[1], peer_id, server_instance)
	if not target.ok:
		return target.error
	if not target.online:
		return "%s must be online." % target.label()

	var res: PlayerResource = target.resource
	var action: String = args[2].to_lower()

	if action == "list":
		return "%s holds: %s" % [
			target.label(),
			", ".join(res.wardstones) if not res.wardstones.is_empty() else "no wardstones"
		]

	if args.size() < 4:
		return "Usage: " + command_usage
	var slug: String = args[3].to_lower()

	match action:
		"grant":
			if res.wardstones.has(slug):
				return "%s already holds the %s Wardstone." % [target.label(), slug.capitalize()]
			res.wardstones.append(slug)
		"revoke":
			var at: int = res.wardstones.find(slug)
			if at < 0:
				return "%s does not hold the %s Wardstone." % [target.label(), slug.capitalize()]
			res.wardstones.remove_at(at)
		_:
			return "Usage: " + command_usage

	# Refresh the client mirror so sealed portals re-skin immediately.
	server_instance.world_server.data_push.rpc_id(
		target.peer_id, &"wardstones.set", {"wardstones": res.wardstones}
	)
	ServerLog.info("GM wardstone %s: '%s' on player #%d." % [action, slug, res.player_id])
	return "%s: %s the %s Wardstone." % [target.label(), "granted" if action == "grant" else "revoked", slug.capitalize()]
