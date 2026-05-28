extends DataRequestHandler
## Returns the top-N rows for a given leaderboard board. The client sends
## { "board": "pvp_week" | ... , "limit": 20 } and gets back { "board", "entries": [{id, name, score, sub}...] }.
## Anyone can query (no permission gating); leaderboards are public by design.


func data_request_handler(peer_id: int, instance: ServerInstance, args: Dictionary) -> Dictionary:
	var board: String = str(args.get("board", ""))
	if board.is_empty():
		return {"error": 1, "ok": false, "message": "Missing board id."}
	var limit: int = int(args.get("limit", 20))
	var entries: Array = LeaderboardService.top_n(instance.world_server, board, limit)
	return {
		"ok": true,
		"board": board,
		"entries": entries,
	}
