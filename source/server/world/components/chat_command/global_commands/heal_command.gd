extends ChatCommand


func _init():
	command_name = 'heal'
	command_priority = 2


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() != 3:
		return "Invalid command format: /heal <target> <amount>"

	var target: int = peer_id if args[1] == "self" else args[1].to_int()
	var amount: int = args[2].to_int()

	var player: Player = server_instance.get_player(target)
	if player == null:
		return "Target not found."

	# Sets current health to the given amount (clamped to max).
	# Doubles as a quick damage tool for testing: /heal self 1
	var stats_component: StatsComponent = player.stats_component
	var new_health: float = clampf(amount, 0.0, stats_component.get_stat(Stat.HEALTH_MAX))
	stats_component.set_stat(Stat.HEALTH, new_health)
	return "/heal %s %d successful" % [str(target), int(new_health)]
