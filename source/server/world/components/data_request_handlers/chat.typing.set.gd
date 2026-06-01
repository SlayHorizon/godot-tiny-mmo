extends DataRequestHandler
## Broadcasts a per-player "is typing" flag to everyone in the sender's
## instance. Triggered by focus_entered / focus_exited on the chat input —
## at most two packets per typing session, regardless of how many keystrokes
## the user actually produces.
##
## Scope is intentionally the whole instance (matches the world-chat
## proximity model). Block list is respected so a recipient who blocked the
## sender doesn't see their typing indicator either.


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var world_server: WorldServer = instance.world_server

	var sender: PlayerResource = world_server.connected_players.get(peer_id)
	if sender == null:
		return {}

	var is_typing: bool = bool(args.get("typing", false))

	var payload: Dictionary = {
		"peer_id": peer_id,
		"id": sender.player_id,
		"typing": is_typing,
	}

	# Broadcast to everyone else in the instance — skip the sender (they
	# don't need to see their own typing indicator) and anyone who has
	# blocked them.
	for other_peer_id: int in instance.connected_peers:
		if other_peer_id == peer_id:
			continue
		var recipient: PlayerResource = world_server.connected_players.get(other_peer_id)
		if recipient == null:
			continue
		if BlockList.is_blocked(recipient.player_id, sender.player_id):
			continue
		world_server.data_push.rpc_id(other_peer_id, &"chat.typing", payload)

	return {}
