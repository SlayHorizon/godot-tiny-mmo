extends DataRequestHandler
## Returns the count of unread, non-deleted mail visible to the requesting
## character — used to badge the launcher's Mail tile. See docs/mailbox.md.


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var pr: PlayerResource = instance.world_server.connected_players.get(peer_id, null)
	if pr == null:
		return {"ok": true, "count": 0}
	return {"ok": true, "count": instance.world_server.database.mail_store.unread_count(pr.player_id)}
