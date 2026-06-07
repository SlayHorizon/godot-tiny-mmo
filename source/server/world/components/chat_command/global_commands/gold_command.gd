extends ChatCommand
## Add gold to a player's inventory (testing / rewards).


func _init() -> void:
	command_name = "gold"
	command_priority = 100 # senior_admin
	command_usage = "/gold <self|@account|#id> <amount>"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() != 3:
		return "Usage: " + command_usage

	var target: CommandTarget.Result = CommandTarget.resolve(args[1], peer_id, server_instance)
	if not target.ok:
		return target.error
	if not target.online:
		return "%s must be online." % target.label()

	var amount: int = args[2].to_int()
	if amount <= 0:
		return "Amount must be positive."

	var res: PlayerResource = target.resource
	Inventory.add_item(res.inventory, Economy.gold_id(), amount)
	return "Gave %d gold to %s. New balance: %d." % [
		amount, target.label(), Inventory.count(res.inventory, Economy.gold_id())
	]
