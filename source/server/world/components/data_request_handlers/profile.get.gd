extends DataRequestHandler

func data_request_handler(peer_id: int, instance: ServerInstance, args: Dictionary) -> Dictionary:
	var ws: WorldServer = instance.world_server

	var from_player: PlayerResource = ws.connected_players.get(peer_id)
	if not from_player:
		return {"error": 1, "ok": false, "name": "Unknown"}

	var target_id: int = int(args.get("id", 0))
	# A world-click sends the target's PEER id (the client doesn't carry the persistent
	# player_id), so resolve it to that connected player's id here.
	if target_id == 0 and args.has("peer"):
		var target: PlayerResource = ws.connected_players.get(int(args["peer"]))
		if target != null:
			target_id = target.player_id
	if target_id == 0:
		target_id = from_player.player_id

	var is_self: bool = target_id == from_player.player_id

	# Step 1 get minimal profile row from DB (works for online and offline)
	var row: Dictionary = ws.database.store.get_player_profile_row(target_id)
	if row.is_empty():
		return {"error": 1, "ok": false, "name": "Unknown"}

	#Step 2: if online, overlay some fields from memory (optional)
	var target_peer_id: int = ws.player_id_to_peer_id.get(target_id, 0)
	var target_player: PlayerResource = ws.connected_players.get(target_peer_id) if target_peer_id != 0 else null
	# Gold is a currency item: balance = amount held in inventory (RAM if online, else DB json).
	var money: int = Inventory.count(
		JSON.parse_string(str(row.get("inventory_json", "{}"))) as Dictionary,
		Economy.gold_id()
	)
	# Resolve the leaderboard counters: live dict in RAM for online, parsed from
	# stats_json on disk for offline. Defaults to empty so missing keys read as 0.
	var lb: Dictionary = {}
	if target_player != null:
		# Keep DB row as base, but override fields that might be more upto date in RAM
		row["display_name"] = target_player.display_name
		row["account_name"] = target_player.account_name
		row["skin_id"] = target_player.skin_id
		row["level"] = target_player.level
		money = Inventory.count(target_player.inventory, Economy.gold_id())
		row["profile_status"] = target_player.profile_status
		row["profile_animation"] = target_player.profile_animation
		row["active_guild_id"] = target_player.active_guild_id
		row["display_title"] = target_player.display_title
		lb = target_player.lb_stats
	else:
		var lb_parsed: Variant = JSON.parse_string(str(row.get("stats_json", "{}")))
		if lb_parsed is Dictionary:
			lb = lb_parsed

	# Step 3 build final response once
	var guild_id: int = int(row.get("active_guild_id", 0))
	var guild_name: String = ws.database.store.get_guild_name(guild_id)if guild_id > 0 else ""

	# Account name is the public "main" handle (like a Discord username); the
	# character display name is just a nickname and may not be unique. The
	# permanent player_id is shown only to staff (moderator and up).
	var mod_priority: int = int(instance.global_role_definitions.get("moderator", {}).get("priority", 1))
	var staff_view: bool = CommandPermissions.effective_priority(from_player, instance) >= mod_priority

	var profile: Dictionary = {
		"name": str(row.get("display_name", "Unknown")),
		"title": str(row.get("display_title", "")),
		"account_name": str(row.get("account_name", "")),
		"skin_id": int(row.get("skin_id", 1)),
		"stats": {
			"money": money,
			"character_class": "???",
			"level": int(row.get("level", 1)),
			# Live played-time for the target. Banked seconds in lb_stats + the
			# current session's elapsed (so an online player's hours count up
			# while you watch).
			"hours": _hours_for(target_player, lb),
			# Leaderboard counters surfaced on the public profile. Defaults to 0
			# when the key has never been written for this player.
			"pve_kills": int(lb.get("pve_kills_total", 0)),
			"pvp_kills": int(lb.get("pvp_kills_total", 0)),
			"arena_wins": int(lb.get("arena_wins", 0)),
			"arena_losses": int(lb.get("arena_losses", 0)),
		},
		"animation": str(row.get("profile_animation", "idle")),
		"description": str(row.get("profile_status", "")),
		"self": is_self,
		"id": target_id,
		"staff_view": staff_view,
		"friend": (not is_self) and from_player.friends.has(target_id),
		# Whether the viewer has the target blocked — the profile panel uses
		# this to flip the "Block" item to "Unblock" without an extra fetch.
		"blocked": (not is_self) and BlockList.is_blocked(from_player.player_id, target_id),
	}

	if not guild_name.is_empty():
		profile["guild_name"] = guild_name

	#Step 4: can_guild_invite (uses inviter's active guild)
	profile["can_guild_invite"] = _can_invite(ws, from_player, target_id, is_self)

	# Public trophy strip — the up-to-3 titles the target pinned to their
	# profile. Shipped to everyone so any viewer sees the same picks.
	profile["displayed_trophies"] = (
		Array(target_player.displayed_trophies) if target_player != null
		else _parse_trophies(row)
	)

	# Self-view extras: full title list + animation list so the edit form can
	# pre-populate without a second round-trip. Only shipped to the owner,
	# never leaks to others.
	if is_self:
		profile["titles_unlocked"] = Array(from_player.titles_unlocked)
		profile["max_displayed_trophies"] = PlayerResource.MAX_DISPLAYED_TROPHIES
		profile["allowed_animations"] = Array(PlayerResource.ALLOWED_PROFILE_ANIMATIONS)
		profile["max_status_len"] = PlayerResource.MAX_PROFILE_STATUS_LEN

	return profile


## Parse displayed_trophies out of an offline player's titles_json row.
static func _parse_trophies(row: Dictionary) -> Array:
	var titles_v: Variant = JSON.parse_string(str(row.get("titles_json", "{}")))
	if titles_v is Dictionary:
		var trophies_v: Variant = (titles_v as Dictionary).get("trophies", [])
		if trophies_v is Array:
			return trophies_v
	return []


## Total played hours, banked seconds + the current session's live elapsed for
## online targets. Returns an int (rounded down) so the UI just renders "67h".
func _hours_for(target_player: PlayerResource, lb: Dictionary) -> int:
	var banked: int = int(lb.get("played_seconds", 0))
	var live: int = 0
	if target_player != null and target_player.session_start_ms > 0:
		live = (Time.get_ticks_msec() - target_player.session_start_ms) / 1000
	return (banked + live) / 3600


func _can_invite(ws: WorldServer, from_player: PlayerResource, target_id: int, is_self: bool) -> bool:
	if is_self:
		return false
	if from_player.active_guild_id <= 0:
		return false

	# Load guild on demand (can add cache later)
	var g: Guild = ws.database.get_guild(from_player.active_guild_id)
	if g == null:
		return false

	if not g.has_permission(from_player.player_id, Guild.Permissions.INVITE):
		return false

	return not g.members.has(target_id)
