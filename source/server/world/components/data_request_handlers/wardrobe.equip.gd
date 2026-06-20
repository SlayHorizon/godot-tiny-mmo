extends DataRequestHandler
## Equip a skin the player owns. Sets the persisted skin_id and updates the synced :skin_id
## state path so every client swaps the sprite live (Character._set_skin_id), mirroring how
## spawn seeds it. The equipping client also applies it locally for instant feedback.


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if not player:
		return {"ok": false}
	var pr: PlayerResource = player.player_resource

	var skin_id: int = int(args.get("skin_id", 0))
	if not pr.owned_skins.has(skin_id):
		return {"ok": false, "reason": "not_owned"}

	pr.skin_id = skin_id
	# Propagate to all clients (including others) so the sprite swaps live.
	player.state_synchronizer.set_by_path(^":skin_id", skin_id)
	return {"ok": true, "skin_id": skin_id}
