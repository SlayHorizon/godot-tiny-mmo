extends DataRequestHandler
## Client → server: the player pressed Recall (the B keybind). Start the recall
## channel — a 5s rooted cast that teleports to the town hub on completion and
## cancels on move (the shared channel root) or damage (cancel_on_damage). The
## channel machinery (push, root, cast bar, cancel) is all reused from the aura;
## recall just rides it with a town-travel payoff. No cooldown — re-press anytime.

const RECALL_ABILITY: RecallAbility = preload("res://source/common/gameplay/combat/ability/ability_collection/channel/recall.tres")


func data_request_handler(peer_id: int, instance: ServerInstance, _args: Dictionary) -> Dictionary:
	if not RateLimiter.check(peer_id, &"recall.start", 4, 1_000):
		return {}
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if player == null or player.is_dead:
		return {}
	# Already channeling something — ignore (a re-press shouldn't restart the cast;
	# cancelling is done by moving).
	if player.get_node_or_null(^"ChannelInstance") != null:
		return {}
	RECALL_ABILITY.use_ability(player, Vector2.ZERO)
	return {}
