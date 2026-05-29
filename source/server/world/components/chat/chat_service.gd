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

	var pushed: Dictionary = {
		"conversation_id": convo_id,
		"text": text,
		"name": sender.display_name,
		"id": sender.player_id,
		"msg_id": int(saved.get("msg_id", 0)),
		"time_ms": now_ms,
	}

	# Push to sender + recipient if online
	var world_server: WorldServer = instance.world_server

	var sender_peer_id: int = int(world_server.player_id_to_peer_id.get(sender.player_id, 0))
	if sender_peer_id > 0:
		WorldServer.curr.data_push.rpc_id(sender_peer_id, &"chat.message", pushed)

	var other_peer_id: int = int(world_server.player_id_to_peer_id.get(other_id, 0))
	if other_peer_id > 0:
		WorldServer.curr.data_push.rpc_id(other_peer_id, &"chat.message", pushed)

	return {}


func get_channel_history(channel: int, limit: int) -> Array:
	if store == null:
		return []

	var convo_id: String = ChatConstants.channel_conversation_id(channel)
	var rows: Array = store.fetch_last(convo_id, limit)
	return _rows_to_payload(rows, convo_id, {"channel": channel})


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
	# Current behavior: broadcast to everyone in the same instance/map.
	return _persist_and_broadcast_to_instance(
		instance,
		player,
		ChatConstants.CHANNEL_WORLD,
		ChatConstants.channel_conversation_id(ChatConstants.CHANNEL_WORLD),
		"global",
		"{}",
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

	var pushed: Dictionary = {
		"conversation_id": convo_id,
		"text": text,
		"channel": ChatConstants.CHANNEL_GUILD,
		"name": player.display_name,
		"id": player.player_id,
		"msg_id": int(saved.get("msg_id", 0)),
		"time_ms": now_ms,
	}

	var ws: WorldServer = instance.world_server
	for peer_id: int in ws.connected_players.keys():
		var p: PlayerResource = ws.connected_players[peer_id]
		if p == null:
			continue
		if p.active_guild_id != guild_id:
			continue
		WorldServer.curr.data_push.rpc_id(peer_id, &"chat.message", pushed)

	return {}


## Ring of recently-broadcast channel messages so the admin dashboard can
## fetch a live tail without scanning the SQLite history every poll. DMs are
## deliberately excluded for privacy.
const RECENT_MAX: int = 100
var recent_channel_messages: Array = []


func _persist_and_broadcast_to_instance(
	instance: ServerInstance,
	player: PlayerResource,
	channel: int,
	convo_id: String,
	convo_type: String,
	meta_json: String,
	text: String
) -> Dictionary:
	if store == null:
		return {"error": 3, "ok": false, "message": "Chat store not initialized."}

	store.ensure_conversation(convo_id, convo_type, meta_json)

	var now_ms: int = int(Time.get_unix_time_from_system() * 1000.0)
	var saved: Dictionary = store.insert_message(convo_id, now_ms, player.player_id, player.display_name, text)

	var pushed: Dictionary = {
		"conversation_id": convo_id,
		"text": text,
		"channel": channel,
		"name": player.display_name,
		"id": player.player_id,
		"msg_id": int(saved.get("msg_id", 0)),
		"time_ms": now_ms,
	}

	# Record an enriched copy for the admin dashboard — pulls fields the
	# clients don't need (account name, instance name) so a moderator can
	# disambiguate two players with the same display name.
	var enriched: Dictionary = pushed.duplicate()
	enriched["account"] = player.account_name
	enriched["channel_name"] = _channel_name(channel)
	enriched["instance"] = ""
	if instance != null and instance.instance_resource != null:
		enriched["instance"] = instance.instance_resource.instance_name
	_record_recent(enriched)

	WorldServer.curr.propagate_rpc(
		WorldServer.curr.data_push.bind(&"chat.message", pushed),
		instance.name
	)

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


func get_system_history(player_id: int, limit: int) -> Array:
	if store == null:
		return []
	if player_id <= 0:
		return []

	var convo_id: String = ChatConstants.system_conversation_id(player_id)
	var rows: Array = store.fetch_last(convo_id, limit)

	return _rows_to_payload(rows, convo_id, {"channel": ChatConstants.CHANNEL_SYSTEM})


func push_system_to_player(instance: ServerInstance, player_id: int, text: String) -> void:
	if store == null:
		return

	var convo_id: String = ChatConstants.system_conversation_id(player_id)
	store.ensure_conversation(convo_id, "system", "{\"player_id\":%d}" % player_id)

	var now_ms: int = int(Time.get_unix_time_from_system() * 1000.0)
	var saved: Dictionary = store.insert_message(
		convo_id,
		now_ms,
		ChatConstants.SYSTEM_SENDER_ID,
		ChatConstants.SYSTEM_SENDER_NAME,
		text
	)

	var pushed: Dictionary = {
		"conversation_id": convo_id,
		"channel": ChatConstants.CHANNEL_SYSTEM,
		"text": text,
		"name": ChatConstants.SYSTEM_SENDER_NAME,
		"id": ChatConstants.SYSTEM_SENDER_ID,
		"msg_id": int(saved.get("msg_id", 0)),
		"time_ms": now_ms,
	}

	# instance is just a handle to the WorldServer for peer-id lookup; some
	# callers (e.g. BasingService scheduled ticks) don't have a per-instance
	# context, so fall back to WorldServer.curr when null.
	var ws: WorldServer = instance.world_server if instance != null else WorldServer.curr
	if ws == null:
		return
	var peer_id: int = int(ws.player_id_to_peer_id.get(player_id, 0))
	if peer_id > 0:
		WorldServer.curr.data_push.rpc_id(peer_id, &"chat.message", pushed)
