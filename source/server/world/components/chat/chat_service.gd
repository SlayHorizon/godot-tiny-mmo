class_name ChatService
extends Node


#const ChatConstants: GDScript = preload("res://source/common/utils/chat_constants.gd")

var store: ChatStoreSqlite


func setup_with_db(db: SQLite) -> void:
	store = ChatStoreSqlite.new(db)


func handle_send_channel_message(
	instance: ServerInstance,
	player: PlayerResource,
	channel: int,
	text: String
) -> Dictionary:
	match channel:
		ChatConstants.CHANNEL_WORLD:
			return _handle_send_world(instance, player, text)
		ChatConstants.CHANNEL_GUILD:
			return _handle_send_guild(instance, player, text)
		ChatConstants.CHANNEL_TEAM:
			return _handle_send_team(instance, player, text)
		ChatConstants.CHANNEL_SYSTEM:
			return {"error": 10, "ok": false, "message": "System is read-only."}
		_:
			return {"error": 11, "ok": false, "message": "Unknown channel."}


func handle_send_dm(
	instance: ServerInstance,
	sender: PlayerResource,
	other_id: int,
	text: String
) -> Dictionary:
	if store == null:
		return {"error": 3, "ok": false, "message": "Chat store not initialized."}

	if other_id <= 0 or other_id == sender.player_id:
		return {"error": 4, "ok": false, "message": "Invalid target."}

	# You can't DM someone you've blocked. Block is asymmetric on the receive
	# side (blocker silently drops blocker's messages), but on the send side
	# we surface a real error — typing into a void with no failure feedback
	# would feel broken, and the user explicitly opted out of contact.
	if BlockList.is_blocked(sender.player_id, other_id):
		return {"error": 5, "ok": false, "message": "You have this player blocked. Unblock to message them."}

	var convo_id: String = ChatConstants.dm_conversation_id(sender.player_id, other_id)
	store.ensure_conversation(convo_id, "dm", "{}")

	var now_ms: int = int(Time.get_unix_time_from_system() * 1000.0)

	var saved: Dictionary = store.insert_message(
		convo_id,
		now_ms,
		sender.player_id,
		sender.display_name,
		text
	)

	var world_server: WorldServer = instance.world_server
	var sender_guild_name: String = ""
	if sender.active_guild_id > 0:
		sender_guild_name = world_server.database.store.get_guild_name(sender.active_guild_id)

	var pushed: Dictionary = {
		"conversation_id": convo_id,
		"text": text,
		"name": sender.display_name,
		"id": sender.player_id,
		"peer_id": sender.current_peer_id,
		"title": sender.display_title,
		"guild_name": sender_guild_name,
		"msg_id": int(saved.get("msg_id", 0)),
		"time_ms": now_ms,
	}

	# Push to sender + recipient if online. Sender always sees their own send
	# (block is asymmetric — they don't know they've been ghosted), but the
	# recipient's push is suppressed if they have the sender blocked.

	var sender_peer_id: int = int(world_server.player_id_to_peer_id.get(sender.player_id, 0))
	if sender_peer_id > 0:
		WorldServer.curr.data_push.rpc_id(sender_peer_id, &"chat.message", pushed)

	var other_peer_id: int = int(world_server.player_id_to_peer_id.get(other_id, 0))
	if other_peer_id > 0 and not BlockList.is_blocked(other_id, sender.player_id):
		WorldServer.curr.data_push.rpc_id(other_peer_id, &"chat.message", pushed)

	return {}


func get_dm_history(self_id: int, other_id: int, limit: int) -> Array:
	if store == null:
		return []

	var convo_id: String = ChatConstants.dm_conversation_id(self_id, other_id)
	var rows: Array = store.fetch_last(convo_id, limit)
	return _rows_to_payload(rows, convo_id, {})


func get_guild_history(guild_id: int, limit: int) -> Array:
	if store == null:
		return []
	if guild_id <= 0:
		return []

	var convo_id: String = ChatConstants.guild_conversation_id(guild_id)
	var rows: Array = store.fetch_last(convo_id, limit)
	return _rows_to_payload(rows, convo_id, {"channel": ChatConstants.CHANNEL_GUILD})


func _handle_send_world(instance: ServerInstance, player: PlayerResource, text: String) -> Dictionary:
	# Broadcast to everyone in the same instance/map. World chat is EPHEMERAL and
	# live-only — never written to SQLite, never replayed on join.
	return _broadcast_world_to_instance(
		instance,
		player,
		ChatConstants.CHANNEL_WORLD,
		ChatConstants.channel_conversation_id(ChatConstants.CHANNEL_WORLD),
		text
	)


func _handle_send_team(instance: ServerInstance, player: PlayerResource, text: String) -> Dictionary:
	# Placeholder: until we have a team/party system.
	# "team:<team_id>" later.
	# For now: either reject or treat as instance-local.
	return {"error": 30, "ok": false, "message": "Team chat not implemented yet."}


func _handle_send_guild(instance: ServerInstance, player: PlayerResource, text: String) -> Dictionary:
	if store == null:
		return {"error": 3, "ok": false, "message": "Chat store not initialized."}

	var guild_id: int = player.active_guild_id
	if guild_id <= 0:
		return {"error": 20, "ok": false, "message": "You are not in a guild."}

	var convo_id: String = ChatConstants.guild_conversation_id(guild_id)
	store.ensure_conversation(convo_id, "guild", "{\"guild_id\":%d}" % guild_id)

	var now_ms: int = int(Time.get_unix_time_from_system() * 1000.0)
	var saved: Dictionary = store.insert_message(
		convo_id,
		now_ms,
		player.player_id,
		player.display_name,
		text
	)

	var ws: WorldServer = instance.world_server
	var guild_name: String = ws.database.store.get_guild_name(guild_id)

	var pushed: Dictionary = {
		"conversation_id": convo_id,
		"text": text,
		"channel": ChatConstants.CHANNEL_GUILD,
		"name": player.display_name,
		"id": player.player_id,
		"peer_id": player.current_peer_id,
		"title": player.display_title,
		"guild_name": guild_name,
		"msg_id": int(saved.get("msg_id", 0)),
		"time_ms": now_ms,
	}

	for peer_id: int in ws.connected_players.keys():
		var p: PlayerResource = ws.connected_players[peer_id]
		if p == null:
			continue
		if p.active_guild_id != guild_id:
			continue
		# Skip recipients who have the sender blocked. Block applies on every
		# channel, not just DM.
		if BlockList.is_blocked(p.player_id, player.player_id):
			continue
		WorldServer.curr.data_push.rpc_id(peer_id, &"chat.message", pushed)

	return {}


## Ring of recently-broadcast channel messages so the admin dashboard can
## fetch a live tail without scanning the SQLite history every poll. DMs are
## deliberately excluded for privacy.
const RECENT_MAX: int = 100
var recent_channel_messages: Array = []

## World (public) + System chat are EPHEMERAL and LIVE-ONLY — never written to SQLite
## and never replayed on join (zone chat in every MMO starts from when you arrive; a
## newly-joined player just sees messages from here on). Guild + DM keep their DB
## history. These monotonic counters mint ids for the unpersisted messages — unique
## within each conversation, which is how the client keys them.
var _world_msg_seq: int = 0
var _system_msg_seq: int = 0


## World (public) chat: broadcast LIVE to everyone in the instance — no persistence,
## no scrollback (live-only, like zone chat in any MMO). Manual peer loop (not
## propagate_rpc) so we can skip recipients who've blocked the sender.
func _broadcast_world_to_instance(
	instance: ServerInstance,
	player: PlayerResource,
	channel: int,
	convo_id: String,
	text: String
) -> Dictionary:
	var now_ms: int = int(Time.get_unix_time_from_system() * 1000.0)
	_world_msg_seq += 1

	var ws_world: WorldServer = instance.world_server
	var world_guild_name: String = ""
	if player.active_guild_id > 0:
		world_guild_name = ws_world.database.store.get_guild_name(player.active_guild_id)

	var pushed: Dictionary = {
		"conversation_id": convo_id,
		"text": text,
		"channel": channel,
		"name": player.display_name,
		"id": player.player_id,
		"peer_id": player.current_peer_id,
		"title": player.display_title,
		"guild_name": world_guild_name,
		"msg_id": _world_msg_seq,
		"time_ms": now_ms,
	}

	# Enriched copy for the admin dashboard tail (account + instance for mod context).
	var enriched: Dictionary = pushed.duplicate()
	enriched["account"] = player.account_name
	enriched["channel_name"] = _channel_name(channel)
	enriched["instance"] = ""
	if instance != null and instance.instance_resource != null:
		enriched["instance"] = instance.instance_resource.instance_name
	_record_recent(enriched)

	var ws_broadcast: WorldServer = instance.world_server
	for peer_id: int in instance.connected_peers:
		var recipient: PlayerResource = ws_broadcast.connected_players.get(peer_id)
		if recipient == null:
			continue
		if BlockList.is_blocked(recipient.player_id, player.player_id):
			continue
		WorldServer.curr.data_push.rpc_id(peer_id, &"chat.message", pushed)

	return {}


func _record_recent(payload: Dictionary) -> void:
	recent_channel_messages.append(payload)
	if recent_channel_messages.size() > RECENT_MAX:
		recent_channel_messages.pop_front()


## Returns the latest [param limit] broadcast channel messages, newest last.
func recent(limit: int = 30) -> Array:
	if limit <= 0 or recent_channel_messages.is_empty():
		return []
	var start: int = maxi(0, recent_channel_messages.size() - limit)
	return recent_channel_messages.slice(start)


## Friendly channel label for the dashboard. Plays nice with future channels
## (custom guild rooms, party voice, etc.) — anything unknown falls through.
static func _channel_name(channel: int) -> String:
	match channel:
		ChatConstants.CHANNEL_WORLD:  return "World"
		ChatConstants.CHANNEL_GUILD:  return "Guild"
		ChatConstants.CHANNEL_TEAM:   return "Team"
		ChatConstants.CHANNEL_SYSTEM: return "System"
		_: return "Ch.%d" % channel


func _rows_to_payload(rows: Array, conversation_id: String, extra: Dictionary) -> Array:
	var out: Array = []

	for r: Dictionary in rows:
		var msg: Dictionary = {
			"conversation_id": conversation_id,
			"text": r.get("text", ""),
			"name": r.get("sender_name", ""),
			"id": int(r.get("sender_id", 0)),
			"msg_id": int(r.get("msg_id", 0)),
			"time_ms": int(r.get("time_ms", 0)),
		}

		for k: Variant in extra.keys():
			msg[k] = extra[k]

		out.append(msg)

	return out


## Send a one-off SYSTEM notice (MOTD, mute/jail/broadcast, level unlock, world-boss
## announce, ...) to one online player. EPHEMERAL like world chat — system notices are
## never persisted, so the per-player system log can't pile up dozens of stale MOTDs
## across logins. A player offline when one fires simply doesn't get it; these are
## courtesy messages (enforcement like mute/jail is applied server-side anyway).
func push_system_to_player(instance: ServerInstance, player_id: int, text: String) -> void:
	# instance is just a handle to the WorldServer for peer-id lookup; some callers
	# (e.g. BasingService scheduled ticks) have no per-instance context, so fall back
	# to WorldServer.curr when null.
	var ws: WorldServer = instance.world_server if instance != null else WorldServer.curr
	if ws == null:
		return
	var peer_id: int = int(ws.player_id_to_peer_id.get(player_id, 0))
	if peer_id <= 0:
		return # offline — system notices aren't stored, so there's nothing to deliver

	_system_msg_seq += 1
	var pushed: Dictionary = {
		"conversation_id": ChatConstants.system_conversation_id(player_id),
		"channel": ChatConstants.CHANNEL_SYSTEM,
		"text": text,
		"name": ChatConstants.SYSTEM_SENDER_NAME,
		"id": ChatConstants.SYSTEM_SENDER_ID,
		"msg_id": _system_msg_seq,
		"time_ms": int(Time.get_unix_time_from_system() * 1000.0),
	}
	WorldServer.curr.data_push.rpc_id(peer_id, &"chat.message", pushed)
