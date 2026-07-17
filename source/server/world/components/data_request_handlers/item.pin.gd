extends DataRequestHandler
## Pins/unpins a bag slot ({"uid": int, "on": bool}). The flag lives on the
## slot dict ("p") inside inventory_json, so it persists with the normal save.


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var player: PlayerResource = instance.world_server.connected_players.get(peer_id)
	if player == null:
		return {"ok": false, "reason": "not_registered"}

	var slot_uid: int = int(args.get("uid", -1))
	var pin: bool = bool(args.get("on", false))
	if not Inventory.set_pinned(player.inventory, slot_uid, pin):
		return {"ok": false, "reason": "no_slot"}
	return {"ok": true}
