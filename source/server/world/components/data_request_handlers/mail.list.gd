extends DataRequestHandler
## Returns the requesting character's inbox (personal mail + this world's
## broadcasts), newest first, each entry with read/claimed flags. Reward details
## stay server-side until claimed — the client only learns there ARE rewards and
## how many. See docs/mailbox.md.


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var pr: PlayerResource = instance.world_server.connected_players.get(peer_id, null)
	if pr == null:
		return {"ok": false}

	var rows: Array = instance.world_server.database.mail_store.inbox_for(pr.player_id)
	var mails: Array = []
	for row: Dictionary in rows:
		var parsed: Variant = JSON.parse_string(str(row.get("attachments_json", "[]")))
		var attachments: Array = parsed if parsed is Array else []
		mails.append({
			"mail_id": int(row.get("mail_id", 0)),
			"sender_name": str(row.get("sender_name", "")),
			"subject": str(row.get("subject", "")),
			"body": str(row.get("body", "")),
			"created_at_ms": int(row.get("created_at_ms", 0)),
			"read": row.get("read_at_ms", null) != null,
			"claimed": row.get("claimed_at_ms", null) != null,
			"rewards": RedeemCodes.describe_grants(attachments),
		})
	# can_send drives the GM-only "New mail" button (server is the real gate — see mail.send).
	var can_send: bool = CommandPermissions.effective_priority(pr, instance) >= 100 # senior_admin
	return {"ok": true, "mails": mails, "can_send": can_send}
