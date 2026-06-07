extends ChatCommand
## Set a player's current health to an amount (clamped to max). Doubles as a quick
## damage tool for testing — /heal self 1 leaves you on 1 HP.


func _init() -> void:
	command_name = "heal"
	command_priority = 2 # admin+
	command_usage = "/heal <self|@account|#id> <amount>"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() != 3:
		return "Usage: " + command_usage

	var target: CommandTarget.Result = CommandTarget.resolve(args[1], peer_id, server_instance)
	if not target.ok:
		return target.error
	var player: Player = CommandTarget.player_node(target, server_instance)
	if player == null:
		return "%s must be online to heal." % target.label()

	var amount: int = args[2].to_int()
	var stats: StatsComponent = player.stats_component
	var new_health: float = clampf(amount, 0.0, stats.get_stat(Stat.HEALTH_MAX))
	stats.set_stat(Stat.HEALTH, new_health)
	return "Set %s to %d HP." % [target.label(), int(new_health)]
