class_name CommandPermissions
## Central place that decides whether a player may run a chat command.
##
## A player's effective priority is the HIGHEST priority among:
##   - the roles persisted on their PlayerResource (server_roles), and
##   - the role granted live via the admin config file (AdminConfig), if any.
## A command runs when its command_priority is <= that effective priority
## (command_priority <= 0 means "anyone").


## The highest role priority this player effectively has.
static func effective_priority(player: PlayerResource, instance: ServerInstance) -> int:
	if player == null:
		return -1

	var best: int = 0
	for role: String in player.server_roles:
		best = maxi(best, _role_priority(instance, role))

	# Live, non-persisted grant from the owner's admin config file.
	var config_role: String = AdminConfig.role_for(player.account_name)
	if not config_role.is_empty():
		best = maxi(best, _role_priority(instance, config_role))

	return best


## Whether this player may run this command right now.
static func can_run(command: ChatCommand, player: PlayerResource, instance: ServerInstance) -> bool:
	if command == null or player == null:
		return false
	if command.command_priority <= 0:
		return true
	return command.command_priority <= effective_priority(player, instance)


static func _role_priority(instance: ServerInstance, role: String) -> int:
	var role_data: Dictionary = instance.global_role_definitions.get(role, {})
	return int(role_data.get("priority", 0))
