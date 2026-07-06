extends DataRequestHandler


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	# Anti-DoS: 20 attack RPCs per second per peer. Weapon cooldowns inside
	# perform_action already drop excess calls, but this short-circuits before
	# the broadcast so a flooder can't even reach propagate_rpc.
	if not RateLimiter.check(peer_id, &"action.perform", 20, 1_000):
		return {}

	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if not player:
		return {}
	# The hand item's abilities are locked mid-cast (the equip-cast). Refuse so a fast
	# swap can't act mid-draw. (Whatever's in hand — weapon or potion — fires its own
	# abilities[0] through this same path once the draw lands.)
	if player.is_equip_casting():
		return {}
	# No abilities mid-channel — the channel IS your action (the client suppresses this too;
	# here is the authoritative gate). A live ChannelInstance rides the caster while it holds.
	if player.get_node_or_null(^"ChannelInstance") != null:
		return {}
	# Stunned (Pinning Arrow): fully locked out — the client is frozen by the push,
	# this is the authoritative backstop.
	if player.is_stunned():
		return {}

	var action_index: int = args.get("i", 0)
	if action_index < 0:
		return {} # negative indices would wrap weapon ability arrays — reject early
	# An ARMED shot override (bow) locks the other abilities — only the basic draw
	# (slot 0) that consumes it stays live. Client mirrors this in Weapon._handle_slot_input.
	if action_index > 0 and player.has_armed_shot():
		return {}
	var action_direction: Vector2 = args.get("d", Vector2.ZERO)
	# "r" marks the RELEASE phase of a two-phase (charge) ability.
	var released: bool = bool(args.get("r", false))
	if player.equipment_component.can_use(&"weapon", action_index, released):
		var weapon_node: Weapon = player.equipment_component.mounted_nodes[&"weapon"] as Weapon
		# Bake aim spread ONCE here (server RNG) so the sprayed direction rides the echo to
		# every peer — the visual bolt then matches the one that actually dealt damage.
		action_direction = weapon_node.aim_with_spread(action_index, action_direction)
		weapon_node.perform_action(action_index, action_direction, released)
		WorldServer.curr.propagate_rpc(
			WorldServer.curr.data_push.bind(
				&"action.perform",
				{"i": action_index, "d": action_direction, "p": peer_id, "r": released}
			),
			instance.name
		)
	return {}
