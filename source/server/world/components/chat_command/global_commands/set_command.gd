extends ChatCommand


func _init():
	command_name = 'set'
	command_priority = 100


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() != 4:
		return "Invalid command format: /set <target> <path> <value>"
	
	var target: int = peer_id if args[1] == "self" else args[1].to_int()
	var path: NodePath = args[2]
	var value: Variant = str_to_var(args[3])

	if path.is_empty() or value == null:
		return "Invalid command format: /set <target> <path> <value>"

	var player: Player = server_instance.get_player(target)
	if not player:
		return "Target not found."

	# Split "Node:property:subproperty" into the node part and the property part,
	# then resolve the node relative to the player exactly like StateSynchronizer's
	# set_by_path does (see PropertyCache). Properties on the player itself use a
	# leading colon, e.g. ":position".
	var node_path: NodePath = TinyNodePath.get_path_to_node(path)
	var property_path: NodePath = TinyNodePath.get_path_to_property(path)
	var target_node: Node = player if node_path.is_empty() else player.get_node_or_null(node_path)

	var error: bool = true
	if target_node and not property_path.is_empty():
		var current_value: Variant = target_node.get_indexed(property_path)
		if current_value != null:
			# Match the existing value's type so e.g. "10" sets a float stat correctly.
			value = type_convert(value, typeof(current_value))
			player.state_synchronizer.set_by_path(path, value)
			error = false

	return ("/set %s %s" % [str(target), str(value)]) + (" successful" if not error else " failed")
