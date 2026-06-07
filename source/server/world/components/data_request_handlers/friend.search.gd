extends DataRequestHandler
## Searches players so the friends menu can find someone to add. A query prefixed
## with "@" matches the stable account name (the @handle); otherwise it matches
## the character / display name. Returns up to [constant RESULT_LIMIT] matches —
## each with id, display name, account name and an online flag — excluding the
## caller. Clicking a result opens that player's profile, where add/remove lives.


## Cap so a broad query (e.g. "a") can't return the whole player table.
const RESULT_LIMIT: int = 20
## Below this the query is too broad to be useful; we skip the DB hit.
const MIN_CHARS: int = 2


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var world_server: WorldServer = instance.world_server
	var store: WorldStoreSqlite = world_server.database.store

	var from_player: PlayerResource = world_server.connected_players.get(peer_id)
	if from_player == null:
		return {"error": 1, "ok": false, "results": []}

	var raw: String = str(args.get("query", "")).strip_edges()
	var by_account: bool = raw.begins_with("@")
	var query: String = raw.substr(1).strip_edges() if by_account else raw
	if query.length() < MIN_CHARS:
		return {"error": 0, "ok": true, "results": [], "msg": "Type at least %d characters." % MIN_CHARS}

	var rows: Array = store.search_players(query, RESULT_LIMIT, by_account)

	var results: Array = []
	for row: Dictionary in rows:
		var pid: int = int(row.get("player_id", 0))
		if pid <= 0 or pid == from_player.player_id:
			continue
		var online_peer_id: int = int(world_server.player_id_to_peer_id.get(pid, 0))
		results.append({
			"id": pid,
			"name": str(row.get("display_name", "")),
			"account": str(row.get("account_name", "")),
			"online": online_peer_id > 0,
			"friend": from_player.friends.has(pid),
		})

	return {"error": 0, "ok": true, "results": results}
