extends ChatCommand
## Scale a player's sprite 1–4× (cosmetic / testing).


func _init() -> void:
	command_name = "size"
	command_priority = 2 # admin+
	command_usage = "/size <self|@account|#id> <1-4>"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() != 3:
		return "Usage: " + command_usage

	var target: CommandTarget.Result = CommandTarget.resolve(args[1], peer_id, server_instance)
	if not target.ok:
		return target.error
	var player: Player = CommandTarget.player_node(target, server_instance)
	if player == null:
		return "%s must be online." % target.label()

	var amount: int = clampi(args[2].to_int(), 1, 4)
	player.state_synchronizer.set_by_path(^":scale", Vector2(amount, amount))
	return "Set %s size to %d." % [target.label(), amount]
