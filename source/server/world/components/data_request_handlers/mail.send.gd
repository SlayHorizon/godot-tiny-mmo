extends DataRequestHandler
## In-game GM composer → send a mail (multiline body, no chat length cap).
## Server-gated by senior-admin priority — same bar as the `/mail` command, so the
## "New mail" button being hidden client-side is convenience, not the security.
## Delegates to MailSender (shared with the chat command). Returns
## {"ok": bool, "message": String}. See docs/mailbox.md.

## Matches the /mail command's command_priority (senior_admin).
const MIN_PRIORITY: int = 100


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var pr: PlayerResource = instance.world_server.connected_players.get(peer_id, null)
	if pr == null:
		return {"ok": false, "message": "Not connected."}
	if CommandPermissions.effective_priority(pr, instance) < MIN_PRIORITY:
		return {"ok": false, "message": "You don't have permission to send mail."}
	return MailSender.compose(
		str(args.get("target", "")),
		str(args.get("subject", "")),
		str(args.get("body", "")),
		str(args.get("attachments", "")),
		peer_id,
		instance,
		str(args.get("from", ""))
	)
