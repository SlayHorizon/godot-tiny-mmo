extends DataRequestHandler
## Returns a guild's event log (newest first), member-only. Args: { q: guild_name }.
## Rows are formatted to display text server-side so every client renders the
## same wording. Entries: [{time_ms, text}, ...]. Written by
## WorldStoreSqlite.add_guild_log at each hooked event (see docs/guild.md).


func data_request_handler(peer_id: int, instance: ServerInstance, args: Dictionary) -> Dictionary:
	var world_server: WorldServer = instance.world_server
	var store: WorldStoreSqlite = world_server.database.store

	var player: PlayerResource = world_server.connected_players.get(peer_id)
	if player == null:
		return {"error": 1, "ok": false, "message": ""}

	var guild_name: String = str(args.get("q", "")).strip_edges()
	if guild_name.is_empty():
		return {"error": 1, "ok": false, "message": ""}
	var guild_id: int = store.get_guild_id_by_name(guild_name)
	if guild_id <= 0:
		return {"error": 1, "ok": false, "message": "Guild not found."}
	var guild: Guild = store.get_guild(guild_id)
	if guild == null or not guild.members.has(player.player_id):
		return {"error": 1, "ok": false, "message": "You're not in this guild."}

	var entries: Array = []
	for row: Dictionary in store.get_guild_log(guild_id):
		entries.append({
			"time_ms": int(row.get("time_ms", 0)),
			"text": _format(row),
		})
	return {"error": 0, "ok": true, "entries": entries}


## One display line per event. Keep wording plain and objective (it's a record,
## not flavor); names were snapshotted at write time.
func _format(row: Dictionary) -> String:
	var actor: String = str(row.get("actor_name", ""))
	var target: String = str(row.get("target_name", ""))
	var data: Dictionary = {}
	var parsed: Variant = JSON.parse_string(str(row.get("data_json", "{}")))
	if parsed is Dictionary:
		data = parsed

	match str(row.get("event", "")):
		"created":
			return "%s founded the guild." % actor
		"joined":
			return "%s joined the guild." % actor
		"left":
			return "%s left the guild." % actor
		"kicked":
			return "%s was kicked by %s." % [target, actor]
		"rank":
			return "%s set %s to %s." % [actor, target, str(data.get("rank", "?"))]
		"perms":
			return "%s updated %s's permissions." % [actor, target]
		"transfer":
			return "%s handed leadership to %s." % [actor, target]
		"deposit":
			return "%s deposited %d gold into the treasury." % [actor, int(data.get("amount", 0))]
		"upgrade":
			return "%s bought %s Lv %d for %d funds." % [
				actor, str(data.get("upgrade", "?")), int(data.get("level", 0)), int(data.get("cost", 0))]
		"logo":
			return "%s unlocked a new guild emblem for %d funds." % [actor, int(data.get("cost", 0))]
		"banner":
			return "%s changed the banner color for %d funds." % [actor, int(data.get("cost", 0))]
		"trophy":
			return "The guild earned the trophy '%s'!" % str(data.get("trophy", "?"))
		"spar_won":
			var won_pts: int = int(data.get("points", 0))
			if won_pts > 0:
				return "Defeated %s in a guild spar (+%d rating)." % [target, won_pts]
			return "Defeated %s in a guild spar." % target
		"spar_lost":
			var lost_pts: int = int(data.get("points", 0))
			if lost_pts > 0:
				return "Lost a guild spar against %s (-%d rating)." % [target, lost_pts]
			return "Lost a guild spar against %s." % target
		"reinforce":
			return "%s reinforced '%s' with %d guards for %d funds." % [
				actor, str(data.get("territory", "?")), int(data.get("count", 0)), int(data.get("cost", 0))]
		"flag_captured":
			if actor.is_empty():
				return "The guild captured '%s'." % str(data.get("territory", "?"))
			return "%s captured '%s' for the guild." % [actor, str(data.get("territory", "?"))]
		"flag_lost":
			return "Lost '%s' to %s." % [str(data.get("territory", "?")), target]
	return "%s %s" % [str(row.get("event", "?")), actor]
