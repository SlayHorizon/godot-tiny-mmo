extends DataRequestHandler
## Buy a skin for a flat price, adding it to the player's owned set. Equipping is a separate
## step (wardrobe.equip). Server-authoritative: validates it's a real player skin, isn't
## already owned, and that the player can pay. The change persists on the world's periodic
## player save (same as shop purchases — no explicit save here).

const SKIN_COST: int = 50


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
	if not PlayerSkins.is_valid(skin_id):
		return {"ok": false, "reason": "invalid"}
	if pr.owned_skins.has(skin_id):
		return {"ok": false, "reason": "owned"}

	var gold_id: int = Economy.gold_id()
	# remove_amount_by_id is all-or-nothing: it removes nothing and returns false if too poor.
	if gold_id <= 0 or not Inventory.remove_amount_by_id(pr.inventory, gold_id, SKIN_COST):
		return {"ok": false, "reason": "no_gold"}

	pr.owned_skins.append(skin_id)
	return {
		"ok": true,
		"skin_id": skin_id,
		"owned": Array(pr.owned_skins),
		"gold": Inventory.count(pr.inventory, Economy.gold_id()),
	}
