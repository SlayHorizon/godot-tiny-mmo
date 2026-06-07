extends ChatCommand
## Grant a server role to an online player and persist it to the DB. Use this for
## staff (moderator/admin). The owner should grant themselves senior_admin via the
## admin config file, not here.


func _init() -> void:
	command_name = "grant"
	command_priority = 100 # senior_admin
	command_usage = "/grant <self|@account|#id> <role>"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() != 3:
		return "Usage: " + command_usage

	var role: String = args[2]
	if not server_instance.global_role_definitions.has(role):
		return "Unknown role '%s'. Known roles: %s" % [
			role, ", ".join(server_instance.global_role_definitions.keys())
		]

	var target: CommandTarget.Result = CommandTarget.resolve(args[1], peer_id, server_instance)
	if not target.ok:
		return target.error
	if not target.online:
		return "%s must be online to grant a role." % target.label()

	target.resource.server_roles[role] = {}
	server_instance.world_server.database.save_player(target.resource)
	return "Granted role '%s' to %s." % [role, target.label()]
