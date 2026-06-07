extends ChatCommand
## Low-level state poke for testing: set any synced property on a player's node
## tree by path. Powerful and unguarded, so it's senior-admin only.
##
## path is StateSynchronizer-style: ":position", "StatsComponent:health", ...


func _init() -> void:
	command_name = "set"
	command_priority = 100 # senior_admin
	command_usage = "/set <self|@account|#id> <path> <value>"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() != 4:
		return "Usage: " + command_usage

	var target: CommandTarget.Result = CommandTarget.resolve(args[1], peer_id, server_instance)
	if not target.ok:
		return target.error
	var player: Player = CommandTarget.player_node(target, server_instance)
	if player == null:
		return "%s must be online." % target.label()

	var path: NodePath = args[2]
	var value: Variant = str_to_var(args[3])
	if path.is_empty() or value == null:
		return "Usage: " + command_usage

	# Split "Node:property" into node + property, resolved relative to the player
	# exactly like StateSynchronizer.set_by_path does. A leading colon targets a
	# property on the player itself, e.g. ":position".
	var node_path: NodePath = TinyNodePath.get_path_to_node(path)
	var property_path: NodePath = TinyNodePath.get_path_to_property(path)
	var target_node: Node = player if node_path.is_empty() else player.get_node_or_null(node_path)
	if target_node == null or property_path.is_empty():
		return "/set failed: bad path '%s'." % str(path)

	var current_value: Variant = target_node.get_indexed(property_path)
	if current_value == null:
		return "/set failed: no value at '%s'." % str(path)

	# Match the existing value's type so e.g. "10" sets a float stat correctly.
	value = type_convert(value, typeof(current_value))
	player.state_synchronizer.set_by_path(path, value)
	return "/set %s %s = %s" % [target.label(), str(path), str(value)]
