extends DataRequestHandler
## Rename: changes the character's display_name for a gold fee. Validation is
## the SAME CredentialsUtils rule set the gateway applies at character creation,
## so a rename can never produce a name creation would have refused. Cost is
## NameChangeInteraction.COST (single source of truth, shared with the dialog
## that shows the price). display_name is a baseline-synced property, so the
## set_by_path below swaps every client's nameplate live; persistence rides the
## normal periodic/logout save_player (display_name is already a saved column).

const CredentialsUtils: GDScript = preload("res://source/common/utils/credentials_utils.gd")


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if not player:
		return {"ok": false}

	var pr: PlayerResource = player.player_resource
	var new_name: String = str(args.get("name", "")).strip_edges()

	# Never trust the client's edit box — same rules, server-side.
	var check: Dictionary = CredentialsUtils.validate_username(new_name)
	if check.get("code", CredentialsUtils.UsernameError.EMPTY) != CredentialsUtils.UsernameError.OK:
		return {"ok": false, "reason": "invalid", "message": str(check.get("message", ""))}

	# Same name → nothing to do (don't charge a no-op).
	if new_name == pr.display_name:
		return {"ok": false, "reason": "same"}

	# Charge the fee — checks + removes atomically (false = can't afford, nothing removed).
	var gold_id: int = Economy.gold_id()
	if gold_id <= 0 or not Inventory.remove_amount_by_id(pr.inventory, gold_id, NameChangeInteraction.COST):
		return {"ok": false, "reason": "gold"}

	var old_name: String = pr.display_name
	pr.display_name = new_name
	# Propagate to all clients (including others) so nameplates swap live.
	player.state_synchronizer.set_by_path(^":display_name", new_name)

	# Renames are moderation-relevant — keep the old→new trail in the log.
	ServerLog.info("Player #%d renamed '%s' -> '%s'." % [pr.player_id, old_name, new_name])
	return {"ok": true, "name": new_name}
