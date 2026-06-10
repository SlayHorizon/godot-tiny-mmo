extends DataRequestHandler
## Snapshot of a duel master's current queue (size + whether the caller is in
## it). Called by the sparring menu on open so the UI reflects existing state.


func data_request_handler(peer_id: int, instance: ServerInstance, args: Dictionary) -> Dictionary:
	var master_id: int = int(args.get("master_id", 0))
	if instance == null or instance.instance_map == null:
		return {"ok": false, "reason": "no_map"}
	var master: DuelMaster = instance.instance_map.get_duel_master(master_id)
	if master == null:
		return {"ok": false, "reason": "no_master"}

	var player: Player = instance.get_player(peer_id)
	if player == null:
		return {"ok": false, "reason": "no_player"}
	# Reject clicks from far away (clients can still click the master's sprite
	# from anywhere on screen — the server is the authority on proximity).
	if player.global_position.distance_to(master.global_position) > 120.0:
		return {"ok": false, "reason": "too_far"}
	# Already fighting elsewhere — block opening a new duel dialog.
	if player.player_resource.in_match:
		return {"ok": false, "reason": "in_match"}

	return SparringService.queue_status(instance, peer_id, master_id)
