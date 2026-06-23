extends DataRequestHandler
## Redeems a code for the requesting character: rate-limits, validates the code,
## checks this character hasn't already claimed it, applies the reward bundle, and
## records the claim on PlayerResource.redeemed_codes. Per-character + online-only
## by design — see docs/redeem_codes.md.
##
## Returns {"ok": true, "rewards": [{"type", "name", "amount"}, ...]}
##      or {"ok": false, "reason": "unknown|expired|already|misconfigured|rate_limited|no_player"}.

## Anti-brute-force: a handful of tries per minute is ample for a human typing a code.
const MAX_ATTEMPTS: int = 5
const WINDOW_MS: int = 60_000


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	if not RateLimiter.check(peer_id, &"redeem.code", MAX_ATTEMPTS, WINDOW_MS):
		return {"ok": false, "reason": "rate_limited"}

	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if player == null or player.player_resource == null:
		return {"ok": false, "reason": "no_player"}
	var pr: PlayerResource = player.player_resource

	var code: String = str(args.get("code", "")).strip_edges().to_upper()
	if code.is_empty():
		return {"ok": false, "reason": "unknown"}

	var entry: Dictionary = RedeemCodes.get_code(code)
	if entry.is_empty():
		return {"ok": false, "reason": "unknown"}
	if RedeemCodes.is_expired(entry):
		return {"ok": false, "reason": "expired"}
	if pr.redeemed_codes.has(code):
		return {"ok": false, "reason": "already"}

	var grants: Array = entry.get("grants", []) as Array
	if grants.is_empty() or not RedeemCodes.validate_grants(grants):
		ServerLog.error("Redeem code '%s' is misconfigured (empty/invalid grants); rejecting." % code)
		return {"ok": false, "reason": "misconfigured"}

	var rewards: Array = RedeemCodes.apply_grants(pr, grants)
	pr.redeemed_codes.append(code)
	ServerLog.info("Player #%d (%s) redeemed code '%s'." % [pr.player_id, pr.display_name, code])
	return {"ok": true, "rewards": rewards}
