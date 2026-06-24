class_name MailSender
extends RefCounted
## Shared server-side "send a mail" logic, used by BOTH the GM `/mail` chat command
## and the in-game GM compose menu (`mail.send` handler) so there's one source of
## truth. Parses reward / `from:` tokens, resolves the target (all / online / #id /
## @account / self), and writes via MailStore. Returns {"ok": bool,
## "message": String}. World-local by design. See docs/mailbox.md.

const DEFAULT_SENDER: String = "System"


## Sends a mail. subject/body are plain strings — the composer supplies them as
## separate fields; the chat command pipe-splits them first. extras_text is the
## comma-separated token string (gold:100, item:1x3, title:Name, from:Sender, …).
static func compose(target: String, subject: String, body: String, extras_text: String, caller_peer_id: int, instance: ServerInstance, sender_override: String = "") -> Dictionary:
	var t: String = target.strip_edges()
	if t.is_empty() or subject.strip_edges().is_empty() or body.strip_edges().is_empty():
		return {"ok": false, "message": "Target, subject and body are all required."}

	var sender: String = DEFAULT_SENDER
	var attachments: Array = []
	if not extras_text.strip_edges().is_empty():
		var parsed: Dictionary = _parse_extras(extras_text)
		if not bool(parsed.get("ok", false)):
			return {"ok": false, "message": str(parsed.get("error", "Bad attachments."))}
		attachments = parsed.get("grants", [])
		var token_sender: String = str(parsed.get("sender", ""))
		if not token_sender.is_empty():
			sender = token_sender
		if not RedeemCodes.validate_grants(attachments):
			return {"ok": false, "message": "One or more attachments are invalid (bad id / amount)."}
	# A dedicated From field (composer) wins over a from: token (chat command).
	if not sender_override.strip_edges().is_empty():
		sender = sender_override.strip_edges()
	var attachments_json: String = JSON.stringify(attachments)

	var store: MailStore = instance.world_server.database.mail_store

	if t == "all":
		store.send(0, sender, subject, body, attachments_json)
		return {"ok": true, "message": "Broadcast mailed to everyone in this world (from %s)." % sender}

	if t == "online":
		var sent: int = 0
		for online_peer_id: int in instance.world_server.connected_players:
			var online_pr: PlayerResource = instance.world_server.connected_players[online_peer_id]
			if online_pr != null:
				store.send(online_pr.player_id, sender, subject, body, attachments_json)
				sent += 1
		return {"ok": true, "message": "Mailed %d online player(s) (from %s)." % [sent, sender]}

	var result: CommandTarget.Result = CommandTarget.resolve(t, caller_peer_id, instance)
	if not result.ok:
		return {"ok": false, "message": result.error}
	if result.player_id <= 0:
		return {"ok": false, "message": "Couldn't resolve a character id — use #<id> (an offline @account can't be targeted)."}
	store.send(result.player_id, sender, subject, body, attachments_json)
	return {"ok": true, "message": "Mailed %s (from %s)." % [result.label(), sender]}


## Parses "gold:100, item:1x3, skin:24, title:Name, xp:500, from:Sender" into grant
## dicts (the redeem shape) + an optional sender override. Comma-separated so a
## title / sender may contain spaces. Returns {"ok": true, "grants": Array,
## "sender": String} or {"ok": false, "error": String}.
static func _parse_extras(text: String) -> Dictionary:
	var grants: Array = []
	var sender: String = ""
	for raw_token: String in text.split(","):
		var token: String = raw_token.strip_edges()
		if token.is_empty():
			continue
		var colon: int = token.find(":")
		if colon < 0:
			return {"ok": false, "error": "Bad token '%s' — use type:value." % token}
		var key: String = token.substr(0, colon).strip_edges().to_lower()
		var val: String = token.substr(colon + 1).strip_edges()
		match key:
			"from":
				sender = val
			"gold":
				grants.append({"type": "currency", "amount": val.to_int()})
			"xp":
				grants.append({"type": "xp", "amount": val.to_int()})
			"skin":
				grants.append({"type": "skin", "id": val.to_int()})
			"title":
				grants.append({"type": "title", "title": val})
			"item":
				var x: int = val.to_lower().find("x")
				if x >= 0:
					grants.append({"type": "item", "id": val.substr(0, x).to_int(), "amount": val.substr(x + 1).to_int()})
				else:
					grants.append({"type": "item", "id": val.to_int(), "amount": 1})
			_:
				return {"ok": false, "error": "Unknown token type '%s'." % key}
	return {"ok": true, "grants": grants, "sender": sender}
