extends DataRequestHandler
## The in-world statue champions: top PvE / PvP / Level, each { name, score, skin_id }. Narrow
## + CACHED in LeaderboardService (skin_id rides ONLY here, never on the leaderboard.top menu
## path). Pulled once by the statue plaza on area-enter; public, no gating.


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	return {"ok": true, "champions": LeaderboardService.champions(instance.world_server)}
