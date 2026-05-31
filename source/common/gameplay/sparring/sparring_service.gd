class_name SparringService
## Server-side 1v1 sparring matchmaker. Each DuelMaster has its own queue and
## hosts one match at a time. Multiple DuelMasters can run in parallel.
##
## Match lifecycle (per master):
##   queue (size 1)               -> waiting, broadcast queue state
##   queue size 2                 -> start_match: teleport, in_match flags up,
##                                   push countdown 3-2-1, then PvP enabled
##   either player dies           -> end_match: tally wins/losses, teleport
##                                   both back to master, clear in_match
##   either player disconnects    -> end_match with the remaining player as
##                                   the winner (or both lose if both gone)
##
## State lives in two static dicts keyed by (instance_name, master_id) — a flat
## composite key keeps the lookup O(1) and avoids per-instance nesting.

const COUNTDOWN_SECONDS: int = 3
const PVP_ENABLE_DELAY_MS: int = COUNTDOWN_SECONDS * 1000

# (instance_name + "::" + master_id) -> Array[peer_id]
static var _queues: Dictionary = {}
# (instance_name + "::" + master_id) -> Dictionary
#   {peer_a, peer_b, master_id, instance_name, pvp_enabled_at_ms, started_ms}
static var _matches: Dictionary = {}
# peer_id -> match key (for fast disconnect / death lookup)
static var _peer_to_match: Dictionary = {}


# --- queue management (called from sparring.queue handler) ---

## Returns a status dict describing the queue after the action. ok=false with
## a reason on validation failures (out of range, master not found, etc.).
static func handle_queue_request(instance: Node, peer_id: int, master_id: int, action: String) -> Dictionary:
	if instance == null or instance.instance_map == null:
		return {"ok": false, "reason": "no_map"}
	var master: DuelMaster = instance.instance_map.get_duel_master(master_id)
	if master == null:
		return {"ok": false, "reason": "no_master"}

	var player: Player = instance.get_player(peer_id)
	if player == null:
		return {"ok": false, "reason": "no_player"}
	# Player must be near the duel master to interact — same UX as warpers/trade.
	if player.global_position.distance_to(master.global_position) > 120.0:
		return {"ok": false, "reason": "too_far"}

	if player.player_resource.in_match:
		return {"ok": false, "reason": "already_in_match"}

	var key: String = _key(instance.name, master_id)
	var queue: Array = _queues.get(key, [])

	match action:
		"join":
			if queue.has(peer_id):
				return _queue_status(instance, master_id, queue, "already_queued")
			# Capacity 2: if we'd be the third, refuse (a match is already starting).
			if queue.size() >= 2:
				return _queue_status(instance, master_id, queue, "full")
			queue.append(peer_id)
			_queues[key] = queue
			if queue.size() == 2:
				_start_match(instance, master, queue[0], queue[1])
				_queues.erase(key)
				_broadcast_queue(instance, master_id, 0)
				return {"ok": true, "queue_size": 0, "started": true}
			_broadcast_queue(instance, master_id, queue.size())
			return _queue_status(instance, master_id, queue, "queued")
		"leave":
			queue.erase(peer_id)
			_queues[key] = queue
			_broadcast_queue(instance, master_id, queue.size())
			return _queue_status(instance, master_id, queue, "left")
		_:
			return {"ok": false, "reason": "bad_action"}


## Snapshot of a duel master's queue. Used by sparring.info.
static func queue_status(instance: Node, peer_id: int, master_id: int) -> Dictionary:
	var key: String = _key(instance.name, master_id)
	var queue: Array = _queues.get(key, [])
	return _queue_status(instance, master_id, queue, "queued" if queue.has(peer_id) else "idle")


# --- match flow ---

static func _start_match(instance: Node, master: DuelMaster, peer_a: int, peer_b: int) -> void:
	var player_a: Player = instance.get_player(peer_a)
	var player_b: Player = instance.get_player(peer_b)
	if player_a == null or player_b == null:
		return # One peer dropped between queue and start; abandon quietly.

	# Teleport via state sync so the move is authoritative and seen by everyone
	# (spectators in the same instance watch from outside the arena walls).
	if master.spawn_a:
		player_a.state_synchronizer.set_by_path(^":position", master.spawn_a.global_position)
		player_a.mark_just_teleported()
	if master.spawn_b:
		player_b.state_synchronizer.set_by_path(^":position", master.spawn_b.global_position)
		player_b.mark_just_teleported()

	# Both fighters start at full HP — a duel with one combatant pre-damaged
	# from PvE isn't a fair test of skill. The new HP propagates to clients
	# automatically via the existing stat-sync delta.
	player_a.stats_component.set_stat(Stat.HEALTH, player_a.stats_component.get_stat(Stat.HEALTH_MAX))
	player_b.stats_component.set_stat(Stat.HEALTH, player_b.stats_component.get_stat(Stat.HEALTH_MAX))

	var now_ms: int = Time.get_ticks_msec()
	var key: String = _key(instance.name, master.master_id)
	_matches[key] = {
		"peer_a": peer_a,
		"peer_b": peer_b,
		"instance_name": instance.name,
		"master_id": master.master_id,
		"started_ms": now_ms,
		"pvp_enabled_at_ms": now_ms + PVP_ENABLE_DELAY_MS,
	}
	_peer_to_match[peer_a] = key
	_peer_to_match[peer_b] = key

	# In-match flag goes up *now* so the deferred PvP-enable check fires at the
	# right time. Damage is still blocked until pvp_enabled_at_ms; the projectile
	# code reads in_match and the per-match timestamp.
	player_a.player_resource.in_match = true
	player_b.player_resource.in_match = true

	# Hook the arena boundary if the designer wired one. Anyone leaving via
	# exploit / map-edge bug instantly loses, see _on_fighter_left_zone.
	if master.fight_zone != null:
		var cb: Callable = _on_fighter_left_zone.bind(key)
		master.fight_zone.body_exited.connect(cb)
		_matches[key]["fight_zone"] = master.fight_zone
		_matches[key]["body_exited_cb"] = cb

	# Tell each client their match started + which spawn point to teleport to.
	# The state-sync set_by_path above gets overwritten on the LocalPlayer by
	# its own input each frame, so we also push the position explicitly here
	# and let LocalPlayer apply it + lock its input briefly.
	var ws: Node = ServerHub.current
	if ws != null:
		ws.data_push.rpc_id(peer_a, &"sparring.match.state", {
			"in_match": true,
			"position": master.spawn_a.global_position if master.spawn_a else Vector2.ZERO,
		})
		ws.data_push.rpc_id(peer_b, &"sparring.match.state", {
			"in_match": true,
			"position": master.spawn_b.global_position if master.spawn_b else Vector2.ZERO,
		})

	_push_countdown(instance, peer_a, peer_b, COUNTDOWN_SECONDS)


## Walks the countdown by emitting a push every second. Each tick we re-check
## that the match still exists (could have been ended by disconnect mid-count).
static func _push_countdown(instance: Node, peer_a: int, peer_b: int, seconds_left: int) -> void:
	var ws: Node = ServerHub.current
	if ws == null:
		return
	if seconds_left <= 0:
		ws.data_push.rpc_id(peer_a, &"sparring.countdown", {"seconds": 0, "text": "FIGHT!"})
		ws.data_push.rpc_id(peer_b, &"sparring.countdown", {"seconds": 0, "text": "FIGHT!"})
		return
	ws.data_push.rpc_id(peer_a, &"sparring.countdown", {"seconds": seconds_left, "text": str(seconds_left)})
	ws.data_push.rpc_id(peer_b, &"sparring.countdown", {"seconds": seconds_left, "text": str(seconds_left)})
	# Use a Tree-bound timer so this survives the static-call context.
	var tree: SceneTree = (ws as Node).get_tree()
	tree.create_timer(1.0).timeout.connect(
		func(): _push_countdown(instance, peer_a, peer_b, seconds_left - 1),
		CONNECT_ONE_SHOT
	)


## Called from Player.die when player_resource.in_match is true. Tally and
## end the match.
static func on_player_died_in_match(loser: Player, killer: Character) -> void:
	var loser_peer: int = int(loser.player_resource.current_peer_id)
	var key: String = str(_peer_to_match.get(loser_peer, ""))
	if key.is_empty() or not _matches.has(key):
		# In-match flag set but no match record — defensive cleanup.
		loser.player_resource.in_match = false
		return
	var match: Dictionary = _matches[key]
	var winner_peer: int = int(match["peer_a"])
	if winner_peer == loser_peer:
		winner_peer = int(match["peer_b"])
	# If the killer is the other fighter, credit the win there. Otherwise (NPC
	# kill, environmental, etc.) nobody wins but the match still ends.
	var killer_peer: int = 0
	if killer is Player:
		killer_peer = int((killer as Player).player_resource.current_peer_id)
	var winner: int = winner_peer if killer_peer == winner_peer else 0
	_end_match(key, loser_peer, winner)


## Called from world_server peer_disconnected. The remaining peer wins by default,
## and any pending queue entry the dropped peer was sitting in gets swept out so
## the next viewer doesn't see a phantom queue count.
static func on_peer_disconnected(peer_id: int) -> void:
	# Sweep queue entries first — a player can be queued without being in an
	# active match.
	var ws: Node = ServerHub.current
	for key: String in _queues.keys():
		var queue: Array = _queues[key]
		if queue.has(peer_id):
			queue.erase(peer_id)
			_queues[key] = queue
			# Re-broadcast so any open menu drops the stale 1/2 → 0/2.
			# Parse the master_id off the composite key (instance::master_id).
			if ws != null:
				var parts: PackedStringArray = key.split("::")
				if parts.size() == 2:
					var instance: Node = ws.instance_manager.get_instance_server_by_id(parts[0])
					_broadcast_queue(instance, parts[1].to_int(), queue.size())

	var key: String = str(_peer_to_match.get(peer_id, ""))
	if key.is_empty() or not _matches.has(key):
		return
	var match: Dictionary = _matches[key]
	var other: int = int(match["peer_a"])
	if other == peer_id:
		other = int(match["peer_b"])
	_end_match(key, peer_id, other)


# --- internals ---

static func _end_match(key: String, loser_peer: int, winner_peer: int) -> void:
	var match: Dictionary = _matches.get(key, {})
	if match.is_empty():
		return

	# Detach the boundary signal first so it can't re-fire during teleport-out
	# and re-end the same match. Safe to no-op if no zone was wired.
	var fz: Area2D = match.get("fight_zone") as Area2D
	var cb: Callable = match.get("body_exited_cb", Callable())
	if fz != null and cb.is_valid() and fz.body_exited.is_connected(cb):
		fz.body_exited.disconnect(cb)

	_matches.erase(key)
	_peer_to_match.erase(int(match["peer_a"]))
	_peer_to_match.erase(int(match["peer_b"]))

	var ws: Node = ServerHub.current
	if ws == null:
		return

	# Locate the instance + master so we can teleport back.
	var instance: Node = ws.instance_manager.get_instance_server_by_id(str(match["instance_name"]))
	var master: DuelMaster = null
	if instance != null and instance.instance_map != null:
		master = instance.instance_map.get_duel_master(int(match["master_id"]))
	var return_pos: Vector2 = master.global_position if master != null else Vector2.ZERO

	# Push the match.state END (with the duel master's position) so LocalPlayer
	# teleports + locks input briefly. The dying player also gets the standard
	# player.died teleport (which now uses the same position via Player.die's
	# in_match override).
	ws.data_push.rpc_id(int(match["peer_a"]), &"sparring.match.state", {"in_match": false, "position": return_pos})
	ws.data_push.rpc_id(int(match["peer_b"]), &"sparring.match.state", {"in_match": false, "position": return_pos})

	# Tally + clear flag + heal-if-alive for each fighter still present.
	_finalize_fighter(ws, instance, int(match["peer_a"]), return_pos, winner_peer == int(match["peer_a"]))
	_finalize_fighter(ws, instance, int(match["peer_b"]), return_pos, winner_peer == int(match["peer_b"]))

	# Announce result in chat — players love to see it.
	var loser_player: PlayerResource = ws.connected_players.get(loser_peer)
	var winner_player: PlayerResource = ws.connected_players.get(winner_peer)
	var msg: String
	if winner_player != null and loser_player != null:
		msg = "⚔ %s defeated %s in a 1v1." % [winner_player.display_name, loser_player.display_name]
	elif loser_player != null:
		msg = "⚔ %s fell in the arena." % loser_player.display_name
	else:
		msg = "⚔ The match ended."
	for peer_id: int in ws.connected_players:
		var p: PlayerResource = ws.connected_players[peer_id]
		if p != null:
			ws.chat_service.push_system_to_player(instance, p.player_id, msg)


static func _finalize_fighter(ws: Node, instance: Node, peer_id: int, return_pos: Vector2, won: bool) -> void:
	var player_res: PlayerResource = ws.connected_players.get(peer_id)
	if player_res == null:
		return
	player_res.in_match = false

	# Tally arena_wins / arena_losses on the persistent lb_stats dict.
	if won:
		player_res.lb_stats["arena_wins"] = int(player_res.lb_stats.get("arena_wins", 0)) + 1
	else:
		player_res.lb_stats["arena_losses"] = int(player_res.lb_stats.get("arena_losses", 0)) + 1

	# Persist now so the result survives a crash before the periodic save.
	ws.database.save_player(player_res)

	if instance == null:
		return
	var player: Player = instance.get_player(peer_id)
	if player == null:
		return
	# State-sync write so other clients see the position update too (the actual
	# LocalPlayer teleport is driven by the sparring.match.state push above).
	player.state_synchronizer.set_by_path(^":position", return_pos)
	player.mark_just_teleported()
	# Heal alive fighters back to full HP. The dying fighter is handled by
	# Player.die's respawn path (which now respawns at the duel master too).
	if not player.is_dead:
		player.stats_component.set_stat(Stat.HEALTH, player.stats_component.get_stat(Stat.HEALTH_MAX))


static func _queue_status(instance: Node, master_id: int, queue: Array, status: String) -> Dictionary:
	return {
		"ok": true,
		"master_id": master_id,
		"queue_size": queue.size(),
		"status": status,
	}


## Broadcast the new queue size to every peer in the instance so any open
## sparring menu updates live without polling.
static func _broadcast_queue(instance: Node, master_id: int, size: int) -> void:
	var ws: Node = ServerHub.current
	if ws == null or instance == null:
		return
	ws.propagate_rpc(
		ws.data_push.bind(&"sparring.queue.update", {
			"master_id": master_id,
			"queue_size": size,
		}),
		instance.name
	)


## Fight-zone Area2D.body_exited callback. If the exiting body is one of the
## two fighters in this match, they instantly lose (anti-exploit / boundary
## escape). Non-fighter bodies (spectators wandering past, NPCs, etc.) are
## ignored.
static func _on_fighter_left_zone(body: Node, key: String) -> void:
	if body is not Player:
		return
	var match: Dictionary = _matches.get(key, {})
	if match.is_empty():
		return
	var leaver_peer: int = int((body as Player).player_resource.current_peer_id)
	var peer_a: int = int(match["peer_a"])
	var peer_b: int = int(match["peer_b"])
	if leaver_peer != peer_a and leaver_peer != peer_b:
		return
	var winner_peer: int = peer_b if leaver_peer == peer_a else peer_a
	_end_match(key, leaver_peer, winner_peer)


static func _key(instance_name: String, master_id: int) -> String:
	return "%s::%d" % [instance_name, master_id]


## The duel master's position for the match this player is in, or Vector2.ZERO
## if not in a match / can't resolve. Used by Player.die to respawn at the duel
## master instead of the map's default spawn.
static func return_position_for(player: Player) -> Vector2:
	if player == null or player.player_resource == null:
		return Vector2.ZERO
	var peer_id: int = int(player.player_resource.current_peer_id)
	var key: String = str(_peer_to_match.get(peer_id, ""))
	if key.is_empty() or not _matches.has(key):
		return Vector2.ZERO
	var match: Dictionary = _matches[key]
	var ws: Node = ServerHub.current
	if ws == null or ws.instance_manager == null:
		return Vector2.ZERO
	var instance: Node = ws.instance_manager.get_instance_server_by_id(str(match["instance_name"]))
	if instance == null or instance.instance_map == null:
		return Vector2.ZERO
	var master: DuelMaster = instance.instance_map.get_duel_master(int(match["master_id"]))
	if master == null:
		return Vector2.ZERO
	return master.global_position


## True if the given player is currently inside an active match where PvP has
## been enabled (countdown has ended). Used by the projectile damage path.
static func is_pvp_live_for(player: Player) -> bool:
	if player == null or player.player_resource == null or not player.player_resource.in_match:
		return false
	var peer_id: int = int(player.player_resource.current_peer_id)
	var key: String = str(_peer_to_match.get(peer_id, ""))
	if key.is_empty() or not _matches.has(key):
		return false
	var match: Dictionary = _matches[key]
	return Time.get_ticks_msec() >= int(match.get("pvp_enabled_at_ms", 0))
