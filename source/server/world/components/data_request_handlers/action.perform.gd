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

	var action_index: int = args.get("i", 0)
	if action_index < 0:
		return {} # negative indices would wrap weapon ability arrays — reject early
	var action_direction: Vector2 = args.get("d", Vector2.ZERO)
	# "r" marks the RELEASE phase of a two-phase (charge) ability.
	var released: bool = bool(args.get("r", false))
	if player.equipment_component.can_use(&"weapon", action_index, released):
		player.equipment_component.mounted_nodes[&"weapon"].perform_action(action_index, action_direction, released)
		WorldServer.curr.propagate_rpc(
			WorldServer.curr.data_push.bind(
				&"action.perform",
				{"i": action_index, "d": action_direction, "p": peer_id, "r": released}
			),
			instance.name
		)
	return {}
