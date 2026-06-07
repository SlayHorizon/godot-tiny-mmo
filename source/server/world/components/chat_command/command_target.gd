class_name CommandTarget
## Unified target resolution for admin chat commands. Every targeted command
## parses its target token through here, so the syntax is identical everywhere:
##
##   self          → the caller
##   @account      → the account's currently-online character (account lookup)
##   #1042 / 1042  → a character by its permanent player_id
##
## Account names are the stable handle: only one character per account can be
## online at a time, so an online @account is unambiguous and is what staff will
## use for most live moderation. A bare or #-prefixed number targets a specific
## character id, which ALSO resolves offline targets (from the DB) for commands
## that support them (mute / jail). For an OFFLINE account whose character id you
## don't know, run /chars <account> to list them, then target by #id.


## Outcome of a resolution attempt. Check [member ok] first; on failure
## [member error] is a ready-to-send player-facing message. On success the
## fields are filled as far as known — online targets carry a live
## [member resource]/[member peer_id]; offline targets carry the
## [member account_name]/[member player_id] resolved from the DB.
class Result extends RefCounted:
	var ok: bool = false
	var error: String = ""
	var online: bool = false
	var peer_id: int = 0
	var player_id: int = 0
	var account_name: String = ""
	var resource: PlayerResource = null
	var display_name: String = ""

	## "Name @account (#id)" for confirmation messages, degrading gracefully when
	## a piece is unknown (e.g. an offline @account with no character resolved
	## reads as just "@account").
	func label() -> String:
		if not display_name.is_empty():
			var acc: String = " @%s" % account_name if not account_name.is_empty() else ""
			var idp: String = " (#%d)" % player_id if player_id > 0 else ""
			return "%s%s%s" % [display_name, acc, idp]
		if not account_name.is_empty():
			return "@%s" % account_name
		return "#%d" % player_id


## Resolve [param token] against the live world. [param caller_peer_id] is the
## player who typed the command (for "self"). Never returns null.
static func resolve(token: String, caller_peer_id: int, instance: ServerInstance) -> Result:
	var r := Result.new()
	var ws: WorldServer = instance.world_server
	var clean: String = token.strip_edges()

	if clean.is_empty():
		r.error = "No target. Use self, @account or #id."
		return r

	# self → the caller.
	if clean == "self":
		var caller: PlayerResource = ws.connected_players.get(caller_peer_id)
		if caller == null:
			r.error = "You're not connected."
			return r
		_fill_online(r, caller_peer_id, caller)
		return r

	# @account → the online character on that account (lowercased to match how
	# accounts are stored). Offline accounts resolve to the name only.
	if clean.begins_with("@"):
		var account: String = clean.substr(1).strip_edges().to_lower()
		if account.is_empty():
			r.error = "Empty account name. Use @name."
			return r
		r.account_name = account
		var peer: int = _online_peer_for_account(account, ws)
		if peer != 0:
			_fill_online(r, peer, ws.connected_players.get(peer))
		else:
			r.ok = true # offline: account known, character ambiguous
			r.online = false
		return r

	# #id / bare number → a character by player_id (online or, via the DB, offline).
	var id_token: String = clean.trim_prefix("#")
	if id_token.is_valid_int():
		var pid: int = id_token.to_int()
		if pid <= 0:
			r.error = "Invalid character id."
			return r
		var peer: int = ws.player_id_to_peer_id.get(pid, 0)
		if peer != 0:
			_fill_online(r, peer, ws.connected_players.get(peer))
			return r
		# Offline: pull account + display name from the DB so account-level
		# actions (mute/jail) still work and confirmations read nicely.
		var row: Dictionary = ws.database.store.get_player_profile_row(pid)
		if row.is_empty():
			r.error = "No character with id %d." % pid
			return r
		r.ok = true
		r.online = false
		r.player_id = pid
		r.account_name = str(row.get("account_name", ""))
		r.display_name = str(row.get("display_name", ""))
		return r

	# A bare word that isn't a number is ambiguous under the @-for-account rule.
	r.error = "Unknown target '%s'. Use self, @account or #id." % clean
	return r


## The live Player NODE for an online target. Searches across instances because
## the target may be in a different map than the caller. null if offline / gone.
static func player_node(r: Result, instance: ServerInstance) -> Player:
	if not r.online or r.peer_id == 0:
		return null
	var inst: ServerInstance = instance.world_server.instance_manager.find_instance_for_peer(r.peer_id)
	return inst.get_player(r.peer_id) if inst != null else null


static func _fill_online(r: Result, peer_id: int, res: PlayerResource) -> void:
	r.ok = true
	r.online = true
	r.peer_id = peer_id
	r.resource = res
	r.player_id = res.player_id
	r.account_name = res.account_name
	r.display_name = res.display_name


static func _online_peer_for_account(account: String, ws: WorldServer) -> int:
	for peer_id: int in ws.connected_players:
		var p: PlayerResource = ws.connected_players[peer_id]
		if p != null and p.account_name.to_lower() == account:
			return peer_id
	return 0
