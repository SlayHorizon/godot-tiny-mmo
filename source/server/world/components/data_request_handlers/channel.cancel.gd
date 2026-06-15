extends DataRequestHandler
## Client → server: the caster moved (or otherwise wants out), so stop their
## active channel. ChannelInstance.cancel() pushes channel.end itself, which
## clears the aura on every client and the root on the caster's. No-op if the
## player has no channel running (a stale cancel after it already ended).


func data_request_handler(peer_id: int, instance: ServerInstance, _args: Dictionary) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if player == null:
		return {}
	var channel: ChannelInstance = player.get_node_or_null(^"ChannelInstance") as ChannelInstance
	if channel != null:
		channel.cancel()
	return {}
