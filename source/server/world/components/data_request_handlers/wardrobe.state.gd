extends DataRequestHandler
## Returns the player's owned skin ids so the wardrobe can mark each skin owned vs locked.
## The equipped skin is the client's own LocalPlayer.skin_id; gold is enforced by
## wardrobe.buy, so this stays lean.


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if not player:
		return {"ok": false}
	return {
		"ok": true,
		"owned": Array(player.player_resource.owned_skins),
		"gold": Inventory.count(player.player_resource.inventory, Economy.gold_id()),
	}
