extends ChatCommand
## Give an item to a player by item id (testing helper).


func _init() -> void:
	command_name = "give"
	command_priority = 100 # senior_admin
	command_usage = "/give <self|@account|#id> <item_id> [amount]"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() < 3 or args.size() > 4:
		return "Usage: " + command_usage

	var target: CommandTarget.Result = CommandTarget.resolve(args[1], peer_id, server_instance)
	if not target.ok:
		return target.error
	if not target.online:
		return "%s must be online." % target.label()

	var item_id: int = args[2].to_int()
	var amount: int = args[3].to_int() if args.size() == 4 else 1
	if item_id <= 0 or amount <= 0:
		return "Invalid item id or amount."

	var item: Item = ContentRegistryHub.load_by_id(&"items", item_id) as Item
	if item == null:
		return "No item with id %d." % item_id

	Inventory.add_item(target.resource.inventory, item_id, amount)
	return "Gave %d x %s (id %d) to %s." % [amount, str(item.item_name), item_id, target.label()]
