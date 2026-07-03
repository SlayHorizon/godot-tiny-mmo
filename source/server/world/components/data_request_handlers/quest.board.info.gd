extends DataRequestHandler
## Returns the player's current daily quest set + progress + claim eligibility.
## Rolls fresh dailies if stale or never rolled (first board click of the day).
## The payload shape is shared with the live daily.progress push (see
## DailyQuestService.build_board_payload).


func data_request_handler(peer_id: int, instance: ServerInstance, args: Dictionary) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if not player:
		return {"ok": false}
	var resource: PlayerResource = player.player_resource
	DailyQuestService.get_or_roll(resource)
	return DailyQuestService.build_board_payload(resource)
