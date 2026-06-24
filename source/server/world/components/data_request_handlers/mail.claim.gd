extends DataRequestHandler
## Claims one mail's reward attachments for the requesting character. Reuses the
## redeem grant pipeline: validate → apply → mark claimed. The claimed guard
## (SQL-level) stops double-claims, including one-claim-per-player on broadcasts.
## Returns {"ok": true, "rewards": [...]} or {"ok": false, "reason": ...}.
## See docs/mailbox.md.


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var pr: PlayerResource = instance.world_server.connected_players.get(peer_id, null)
	if pr == null:
		return {"ok": false, "reason": "no_player"}
	var mail_id: int = int(args.get("mail_id", 0))
	if mail_id <= 0:
		return {"ok": false, "reason": "missing"}

	var store: MailStore = instance.world_server.database.mail_store
	var claimable: Dictionary = store.get_claimable(pr.player_id, mail_id)
	if not bool(claimable.get("ok", false)):
		return {"ok": false, "reason": str(claimable.get("reason", "missing"))}

	var attachments: Array = claimable.get("attachments", [])
	if not RedeemCodes.validate_grants(attachments):
		ServerLog.error("Mail #%d has invalid attachments; refusing to claim." % mail_id)
		return {"ok": false, "reason": "invalid"}

	var rewards: Array = RedeemCodes.apply_grants(pr, attachments)
	store.mark_claimed(pr.player_id, mail_id)
	ServerLog.info("Player #%d (%s) claimed mail #%d." % [pr.player_id, pr.display_name, mail_id])
	return {"ok": true, "rewards": rewards}
