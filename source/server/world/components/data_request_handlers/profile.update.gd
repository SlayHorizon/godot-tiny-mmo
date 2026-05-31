extends DataRequestHandler
## Self-only profile customization. The caller edits their own profile fields
## (status text, display title, profile animation) from the Edit panel on the
## player profile menu. Each field is optional — only sent keys are applied,
## so the client can ship partial updates.
##
## Validation:
##   • display_title must be empty OR already in titles_unlocked (no inventing).
##   • profile_status is trimmed and capped at MAX_PROFILE_STATUS_LEN.
##   • profile_animation must be one of ALLOWED_PROFILE_ANIMATIONS.
## Failure returns {"ok": false, "reason": "..."} and leaves all fields untouched.


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var ws: WorldServer = instance.world_server
	var player: PlayerResource = ws.connected_players.get(peer_id)
	if player == null:
		return {"ok": false, "reason": "not_connected"}

	# Validate everything BEFORE mutating so a partial write can't slip through
	# when the second field is bad.
	var new_title: Variant = null
	if args.has("display_title"):
		var requested_title: String = str(args["display_title"])
		if not requested_title.is_empty() and not player.titles_unlocked.has(requested_title):
			return {"ok": false, "reason": "title_locked"}
		new_title = requested_title

	var new_status: Variant = null
	if args.has("profile_status"):
		var raw: String = str(args["profile_status"]).strip_edges()
		if raw.length() > PlayerResource.MAX_PROFILE_STATUS_LEN:
			raw = raw.substr(0, PlayerResource.MAX_PROFILE_STATUS_LEN)
		new_status = raw

	var new_animation: Variant = null
	if args.has("profile_animation"):
		var anim: String = str(args["profile_animation"])
		if not PlayerResource.ALLOWED_PROFILE_ANIMATIONS.has(anim):
			return {"ok": false, "reason": "bad_animation"}
		new_animation = anim

	# Trophy strip: an Array of strings, capped at MAX_DISPLAYED_TROPHIES, each
	# entry validated against titles_unlocked (no "showing a title you haven't
	# earned"). Order matters — preserved client-side as the chip order.
	var new_trophies: Variant = null
	if args.has("displayed_trophies"):
		var raw_v: Variant = args["displayed_trophies"]
		var raw_arr: Array = raw_v if raw_v is Array else []
		var cleaned: PackedStringArray = []
		for entry: Variant in raw_arr:
			var t: String = str(entry)
			if t.is_empty():
				continue
			if not player.titles_unlocked.has(t):
				return {"ok": false, "reason": "trophy_locked"}
			if cleaned.has(t):
				continue # de-dupe silently
			cleaned.append(t)
			if cleaned.size() >= PlayerResource.MAX_DISPLAYED_TROPHIES:
				break
		new_trophies = cleaned

	# All validated — commit.
	if new_title != null:
		player.display_title = new_title
	if new_status != null:
		player.profile_status = new_status
	if new_animation != null:
		player.profile_animation = new_animation
	if new_trophies != null:
		player.displayed_trophies = new_trophies

	return {
		"ok": true,
		"display_title": player.display_title,
		"profile_status": player.profile_status,
		"profile_animation": player.profile_animation,
		"displayed_trophies": Array(player.displayed_trophies),
	}
