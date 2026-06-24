extends DataRequestHandler
## Soft-deletes one mail for the requesting character (a broadcast stays for
## everyone else). See docs/mailbox.md.


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var pr: PlayerResource = instance.world_server.connected_players.get(peer_id, null)
	if pr == null:
		return {"ok": false}
	var mail_id: int = int(args.get("mail_id", 0))
	if mail_id <= 0:
		return {"ok": false}
	instance.world_server.database.mail_store.soft_delete(pr.player_id, mail_id)
	return {"ok": true}
