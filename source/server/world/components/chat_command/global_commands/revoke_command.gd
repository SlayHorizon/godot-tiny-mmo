extends ChatCommand
## Remove a persisted server role from an online player and save. Roles granted
## via the admin config file are live and can't be revoked here — remove the
## account from the admin config instead.


func _init() -> void:
	command_name = "revoke"
	command_priority = 100 # senior_admin
	command_usage = "/revoke <self|@account|#id> <role>"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() != 3:
		return "Usage: " + command_usage

	var role: String = args[2]
	var target: CommandTarget.Result = CommandTarget.resolve(args[1], peer_id, server_instance)
	if not target.ok:
		return target.error
	if not target.online:
		return "%s must be online to revoke a role." % target.label()

	if not target.resource.server_roles.has(role):
		return "%s does not have the role '%s'." % [target.label(), role]

	target.resource.server_roles.erase(role)
	server_instance.world_server.database.save_player(target.resource)
	return "Revoked role '%s' from %s." % [role, target.label()]
