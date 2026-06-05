extends DataRequestHandler
## Toggles the player's active guild "tag". Args: { guild_name }. Tagging into a
## guild (or untagging) only works in a safe zone, with a cooldown, to stop
## tag-swapping to dodge friendly-fire / glory consequences. The tag drives
## guild chat, basing affiliation, and (later) friendly fire — all of which key
## off active_guild_id, so just setting it here activates them.

## Cooldown between tag changes (per player, in-memory — resets on restart).
const TAG_COOLDOWN_MS: int = 30000

static var _last_tag_ms: Dictionary[int, int] = {}


func data_request_handler(peer_id: int, instance: ServerInstance, args: Dictionary) -> Dictionary:
	var world_server: WorldServer = instance.world_server
	var store: WorldStoreSqlite = world_server.database.store

	var player: PlayerResource = world_server.connected_players.get(peer_id)
	if player == null:
		return {"error": 1, "ok": false, "message": ""}
	var player_node: Player = instance.players_by_peer_id.get(peer_id)
	if player_node == null:
		return {"error": 1, "ok": false, "message": ""}

	var guild_name: String = str(args.get("guild_name", "")).strip_edges()
	if guild_name.is_empty():
		return {"error": 1, "ok": false, "message": ""}
	var guild_id: int = store.get_guild_id_by_name(guild_name)
	if guild_id <= 0:
		return {"error": 1, "ok": false, "message": "Guild not found."}
	var guild: Guild = store.get_guild(guild_id)
	if guild == null or not guild.members.has(player.player_id):
		return {"error": 1, "ok": false, "message": "You're not in this guild."}

	# Safe-zone gate.
	if player_node.is_pvp():
		return {"error": 1, "ok": false, "message": "You can only change your guild tag in a safe zone."}

	# Cooldown gate.
	var now_ms: int = Time.get_ticks_msec()
	var last_ms: int = int(_last_tag_ms.get(player.player_id, 0))
	if last_ms > 0 and now_ms - last_ms < TAG_COOLDOWN_MS:
		var secs: int = int(ceil((TAG_COOLDOWN_MS - (now_ms - last_ms)) / 1000.0))
		return {"error": 1, "ok": false, "message": "Wait %ds before changing your tag again." % secs}

	# Tag cap: how many members may be online & tagged at once (Member Capacity
	# upgrade raises it). Only gates tagging IN — untagging is always allowed.
	var was_active: bool = player.active_guild_id == guild_id
	if not was_active:
		var cap: int = GuildUpgrades.tag_cap(guild)
		var tagged_online: int = 0
		for pid: int in world_server.connected_players:
			var other: PlayerResource = world_server.connected_players[pid]
			if other != null and other.active_guild_id == guild_id:
				tagged_online += 1
		if tagged_online >= cap:
			return {"error": 1, "ok": false, "message": "Tag limit reached (%d online). Upgrade Member Capacity or wait for a slot." % cap}

	# Toggle the tag.
	player.active_guild_id = 0 if was_active else guild_id
	_last_tag_ms[player.player_id] = now_ms
	store.save_player(player)
	# Keep the client's ClientState.active_guild_id in sync (drives ally tints etc.).
	world_server.data_push.rpc_id(peer_id, &"active_guild_id.set", {"active_guild_id": player.active_guild_id})
	# Sync the player node's tag so OTHER players re-tint this player's ally bar live.
	var pnode: Player = instance.players_by_peer_id.get(peer_id)
	if pnode != null:
		pnode.state_synchronizer.set_by_path(^":active_guild_id", player.active_guild_id)

	var message: String = ("Untagged from %s." % guild.guild_name) if was_active else ("Tagged into %s." % guild.guild_name)
	world_server.chat_service.push_system_to_player(instance, player.player_id, message)
	return {"error": 0, "ok": true, "message": message, "is_active": not was_active}
