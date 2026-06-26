class_name SparringService
## Server-side spar matchmaker for N teams of any sizes — the station's SparTeam
## children define how many teams and how many slots each has (1v1, 2v2, 1v3,
## 1v1v1, ...). Each DuelMaster station runs one match at a time; stations run
## in parallel.
##
## Pick-a-side: players join a team slot; when EVERY team is full the match
## starts. Default rules (see SparGameMode for the override hooks): fighters
## keep their own stats, and LAST TEAM STANDING wins — a dead fighter is out
## and the match continues until at most one team has fighters left. Friendly
## fire is OFF (see can_spar_damage).
##
## State lives in static dicts keyed by (instance_name, master_id).

const COUNTDOWN_SECONDS: int = 3
const PVP_ENABLE_DELAY_MS: int = COUNTDOWN_SECONDS * 1000

# key -> Array[Array[peer_id]] — one roster per team, indexed like master.teams().
static var _queues: Dictionary = {}
# key -> match dict (see _start_match)
static var _matches: Dictionary = {}
# peer_id -> match key (active fighters only; cleared the moment a fighter is out)
static var _peer_to_match: Dictionary = {}


# --- queue management -------------------------------------------------------

static func handle_queue_request(instance: Node, peer_id: int, master_id: int, action: String, team_index: int = -1) -> Dictionary:
	if instance == null or instance.instance_map == null:
		return {"ok": false, "reason": "no_map"}
	var master: DuelMaster = instance.instance_map.get_duel_master(master_id)
	if master == null:
		return {"ok": false, "reason": "no_master"}
	var teams: Array[SparTeam] = master.teams()
	if teams.size() < 2:
		return {"ok": false, "reason": "bad_station"}
	var player: Player = instance.get_player(peer_id)
	if player == null:
		return {"ok": false, "reason": "no_player"}
	if player.global_position.distance_to(master.global_position) > 120.0:
		return {"ok": false, "reason": "too_far"}
	if player.player_resource.in_match:
		return {"ok": false, "reason": "already_in_match"}

	var key: String = _key(instance.name, master_id)
	var queue: Array = _queues.get(key, _empty_queue(teams.size()))

	match action:
		"leave":
			for roster: Array in queue:
				roster.erase(peer_id)
			_queues[key] = queue
			_broadcast_queue(instance, master, queue)
			return _queue_status(master, queue, peer_id, "left")
		"join":
			if team_index < 0 or team_index >= teams.size():
				return {"ok": false, "reason": "bad_team"}
			for roster: Array in queue:
				if roster.has(peer_id):
					return _queue_status(master, queue, peer_id, "already_queued")
			var roster: Array = queue[team_index]
			if roster.size() >= teams[team_index].capacity():
				return _queue_status(master, queue, peer_id, "team_full")
			roster.append(peer_id)
			_queues[key] = queue
			if _all_full(queue, teams):
				var rosters: Array = []
				for r: Array in queue:
					rosters.append(r.duplicate())
				_queues.erase(key)
				_start_match(instance, master, rosters)
				_broadcast_queue(instance, master, _empty_queue(teams.size()))
				return {"ok": true, "started": true}
			_broadcast_queue(instance, master, queue)
			return _queue_status(master, queue, peer_id, "queued")
		_:
			return {"ok": false, "reason": "bad_action"}


## Snapshot of a station's rosters (+ which team the caller sits in). sparring.info.
static func queue_status(instance: Node, peer_id: int, master_id: int) -> Dictionary:
	var master: DuelMaster = null
	if instance != null and instance.instance_map != null:
		master = instance.instance_map.get_duel_master(master_id)
	if master == null:
		return {"ok": false, "reason": "no_master"}
	var queue: Array = _queues.get(_key(instance.name, master_id), _empty_queue(master.teams().size()))
	return _queue_status(master, queue, peer_id, "idle")


# --- match flow -------------------------------------------------------------

static func _start_match(instance: Node, master: DuelMaster, rosters: Array) -> void:
	var teams: Array[SparTeam] = master.teams()
	var now_ms: int = Time.get_ticks_msec()
	var key: String = _key(instance.name, master.master_id)
	var alive: Dictionary = {}
	var team_of: Dictionary = {}
	_matches[key] = {
		"rosters": rosters, "alive": alive, "team_of": team_of,
		"instance_name": instance.name, "master_id": master.master_id,
		"started_ms": now_ms, "pvp_enabled_at_ms": now_ms + PVP_ENABLE_DELAY_MS,
	}

	var ws: WorldServer = WorldServer.curr
	var all_peers: Array = []
	var flat_all: Array = []
	for r: Array in rosters:
		flat_all.append_array(r)
	for t: int in rosters.size():
		var spawns: Array[Marker2D] = teams[t].spawns()
		for i: int in (rosters[t] as Array).size():
			var peer: int = rosters[t][i]
			all_peers.append(peer)
			team_of[peer] = t
			_peer_to_match[peer] = key
			var player: Player = instance.get_player(peer)
			if player == null:
				alive[peer] = false # dropped between queue + start; counts as out
				continue
			alive[peer] = true
			var spawn_pos: Vector2 = master.global_position
			if i < spawns.size() and spawns[i] != null:
				spawn_pos = spawns[i].global_position
			player.state_synchronizer.set_by_path(^":position", spawn_pos)
			player.mark_just_teleported()
			# Full HP — a duel where one fighter is PvE-chipped isn't a fair test.
			player.stats_component.set_stat(Stat.HEALTH, player.stats_component.get_stat(Stat.HEALTH_MAX))
			# Mode hook (default: keep the player's own stats untouched).
			if master.game_mode != null:
				master.game_mode.apply_to_fighter(player)
			player.player_resource.in_match = true
			if ws != null:
				# Allies/opponents (peer ids) ride along so the client can tint
				# health bars by SPAR team, overriding guild colors for the match.
				var allies: Array = (rosters[t] as Array).duplicate()
				allies.erase(peer)
				var opponents: Array = []
				for p: int in flat_all:
					if not (rosters[t] as Array).has(p):
						opponents.append(p)
				ws.data_push.rpc_id(peer, &"sparring.match.state", {
					"in_match": true,
					"position": spawn_pos,
					"allies": allies,
					"opponents": opponents,
				})

	if master.fight_zone != null:
		var cb: Callable = _on_fighter_left_zone.bind(key)
		master.fight_zone.body_exited.connect(cb)
		_matches[key]["fight_zone"] = master.fight_zone
		_matches[key]["body_exited_cb"] = cb

	# Degenerate case: a whole team dropped between queue and start.
	if _check_elimination(key):
		return
	_push_countdown(instance, all_peers, COUNTDOWN_SECONDS)


static func _push_countdown(instance: Node, peers: Array, seconds_left: int) -> void:
	var ws: WorldServer = WorldServer.curr
	if ws == null:
		return
	var payload: Dictionary = (
		{"seconds": 0, "text": "FIGHT!"} if seconds_left <= 0
		else {"seconds": seconds_left, "text": str(seconds_left)}
	)
	for peer: int in peers:
		ws.data_push.rpc_id(peer, &"sparring.countdown", payload)
	if seconds_left <= 0:
		return
	var tree: SceneTree = (ws as Node).get_tree()
	tree.create_timer(1.0).timeout.connect(
		func() -> void: _push_countdown(instance, peers, seconds_left - 1),
		CONNECT_ONE_SHOT
	)


## Called from Player.die when in_match. Marks the fighter out; if at most one
## team still has fighters the match ends. Player.die handles teleporting them
## (via return_position_for, called BEFORE this).
static func on_player_died_in_match(loser: Player, _killer: Character) -> void:
	var loser_peer: int = int(loser.player_resource.current_peer_id)
	var key: String = str(_peer_to_match.get(loser_peer, ""))
	if key.is_empty() or not _matches.has(key):
		loser.player_resource.in_match = false
		return
	(_matches[key]["alive"] as Dictionary)[loser_peer] = false
	loser.player_resource.in_match = false # out → harmless spectator while it continues
	_peer_to_match.erase(loser_peer)
	_check_elimination(key)


## Sweep a disconnecting peer out of any queue, and treat an in-match disconnect
## as a death (their team may now be eliminated).
static func on_peer_disconnected(peer_id: int) -> void:
	_sweep_queues(peer_id)
	var mkey: String = str(_peer_to_match.get(peer_id, ""))
	if mkey.is_empty() or not _matches.has(mkey):
		return
	(_matches[mkey]["alive"] as Dictionary)[peer_id] = false
	_peer_to_match.erase(peer_id)
	_check_elimination(mkey)


## Leaving the instance (warp / recall) drops the peer from any spar QUEUE — the
## same hygiene dungeon's on_player_left does. A mid-match fighter can't warp out
## (fight_zone + the in_match lock), and a real disconnect goes through
## on_peer_disconnected, so sweeping the queue is all that's needed here. Wired
## from InstanceManager.player_switch_instance.
static func on_player_left(peer_id: int, _instance: Node) -> void:
	_sweep_queues(peer_id)


## Drop a peer from every spar queue and refresh the affected stations' rosters.
static func _sweep_queues(peer_id: int) -> void:
	var ws: WorldServer = WorldServer.curr
	for key: String in _queues.keys():
		var queue: Array = _queues[key]
		var was_queued: bool = false
		for roster: Array in queue:
			if roster.has(peer_id):
				roster.erase(peer_id)
				was_queued = true
		if not was_queued:
			continue
		_queues[key] = queue
		if ws != null:
			var parts: PackedStringArray = key.split("::")
			if parts.size() == 2:
				var instance: Node = ws.instance_manager.get_instance_server_by_id(parts[0])
				var master: DuelMaster = null
				if instance != null and instance.instance_map != null:
					master = instance.instance_map.get_duel_master(parts[1].to_int())
				_broadcast_queue(instance, master, queue)


# --- internals --------------------------------------------------------------

static func _empty_queue(team_count: int) -> Array:
	var out: Array = []
	for _i: int in team_count:
		out.append([])
	return out


static func _all_full(queue: Array, teams: Array[SparTeam]) -> bool:
	for t: int in teams.size():
		if (queue[t] as Array).size() < teams[t].capacity():
			return false
	return true


## Ends the match if at most one team still has living fighters. True if ended.
static func _check_elimination(key: String) -> bool:
	var match_data: Dictionary = _matches.get(key, {})
	if match_data.is_empty():
		return false
	var last_alive: int = -1
	var alive_teams: int = 0
	for t: int in (match_data["rosters"] as Array).size():
		if _alive_count(match_data, t) > 0:
			alive_teams += 1
			last_alive = t
	if alive_teams > 1:
		return false
	_end_match(key, last_alive) # -1 = everyone down = draw
	return true


static func _alive_count(match_data: Dictionary, team_index: int) -> int:
	var alive: Dictionary = match_data["alive"]
	var n: int = 0
	for peer: int in (match_data["rosters"] as Array)[team_index]:
		if alive.get(peer, false):
			n += 1
	return n


static func _end_match(key: String, winner_index: int) -> void:
	var match_data: Dictionary = _matches.get(key, {})
	if match_data.is_empty():
		return

	var fz: Area2D = match_data.get("fight_zone") as Area2D
	var cb: Callable = match_data.get("body_exited_cb", Callable())
	if fz != null and cb.is_valid() and fz.body_exited.is_connected(cb):
		fz.body_exited.disconnect(cb)

	_matches.erase(key)
	var rosters: Array = match_data["rosters"]
	for roster: Array in rosters:
		for peer: int in roster:
			if _peer_to_match.get(peer) == key:
				_peer_to_match.erase(peer)

	var ws: WorldServer = WorldServer.curr
	if ws == null:
		return
	var instance: Node = ws.instance_manager.get_instance_server_by_id(str(match_data["instance_name"]))
	var master: DuelMaster = null
	if instance != null and instance.instance_map != null:
		master = instance.instance_map.get_duel_master(int(match_data["master_id"]))
	var return_pos: Vector2 = master.global_position if master != null else Vector2.ZERO

	for t: int in rosters.size():
		for peer: int in rosters[t]:
			_finalize_fighter(ws, instance, master, peer, return_pos, t == winner_index)
			ws.data_push.rpc_id(peer, &"sparring.match.state", {"in_match": false, "position": return_pos})

	_announce_result(ws, instance, master, rosters, winner_index)


static func _finalize_fighter(ws: Node, instance: Node, master: DuelMaster, peer_id: int, return_pos: Vector2, won: bool) -> void:
	var player_res: PlayerResource = ws.connected_players.get(peer_id)
	if player_res == null:
		return
	player_res.in_match = false
	if won:
		player_res.lb_stats["arena_wins"] = int(player_res.lb_stats.get("arena_wins", 0)) + 1
	else:
		player_res.lb_stats["arena_losses"] = int(player_res.lb_stats.get("arena_losses", 0)) + 1
	ws.database.save_player(player_res)

	if instance == null:
		return
	var player: Player = instance.get_player(peer_id)
	if player == null:
		return
	# Undo whatever the mode applied (default mode: nothing to undo).
	if master != null and master.game_mode != null:
		master.game_mode.remove_from_fighter(player)
	player.state_synchronizer.set_by_path(^":position", return_pos)
	player.mark_just_teleported()
	if not player.is_dead:
		player.stats_component.set_stat(Stat.HEALTH, player.stats_component.get_stat(Stat.HEALTH_MAX))


static func _announce_result(ws: Node, instance: Node, master: DuelMaster, rosters: Array, winner_index: int) -> void:
	var msg: String
	if winner_index < 0:
		msg = "⚔ The match ended in a draw."
	else:
		var losers: Array = []
		for t: int in rosters.size():
			if t != winner_index:
				losers.append_array(_names(rosters[t]))
		msg = "⚔ %s defeated %s%s." % [
			", ".join(_names(rosters[winner_index])),
			", ".join(losers),
			"" if master == null else " at %s" % master.master_name,
		]
	for peer: int in ws.connected_players:
		var p: PlayerResource = ws.connected_players[peer]
		if p != null:
			ws.chat_service.push_system_to_player(instance, p.player_id, msg)


static func _queue_status(master: DuelMaster, queue: Array, peer_id: int, status: String) -> Dictionary:
	var your_team: int = -1
	for t: int in queue.size():
		if (queue[t] as Array).has(peer_id):
			your_team = t
			break
	var snapshot: Dictionary = _teams_snapshot(master, queue)
	snapshot["ok"] = true
	snapshot["master_id"] = master.master_id
	snapshot["master_name"] = master.master_name
	snapshot["your_team"] = your_team
	snapshot["status"] = status
	return snapshot


## {teams: [names...], capacities: [int...], team_names: [String...]} for the lobby.
static func _teams_snapshot(master: DuelMaster, queue: Array) -> Dictionary:
	var teams: Array[SparTeam] = master.teams()
	var rosters: Array = []
	var capacities: Array = []
	var team_names: Array = []
	for t: int in teams.size():
		var roster: Array = queue[t] if t < queue.size() else []
		rosters.append(_names(roster))
		capacities.append(teams[t].capacity())
		team_names.append(_team_label(teams[t], t, roster))
	return {"teams": rosters, "capacities": capacities, "team_names": team_names}


## Team label fallback chain: authored team_name → the guild of the first queued
## member who has one (nice for guild-vs-guild lobbies) → plain "Team N".
static func _team_label(team: SparTeam, index: int, peers: Array) -> String:
	if not team.team_name.is_empty():
		return team.team_name
	var ws: WorldServer = WorldServer.curr
	if ws != null:
		for peer: int in peers:
			var pr: PlayerResource = ws.connected_players.get(peer)
			if pr != null and pr.active_guild_id > 0:
				var guild_name: String = ws.database.store.get_guild_name(pr.active_guild_id)
				if not guild_name.is_empty():
					return guild_name
	return "Team %d" % (index + 1)


static func _broadcast_queue(instance: Node, master: DuelMaster, queue: Array) -> void:
	var ws: WorldServer = WorldServer.curr
	if ws == null or instance == null or master == null:
		return
	var payload: Dictionary = _teams_snapshot(master, queue)
	payload["master_id"] = master.master_id
	ws.propagate_rpc(
		ws.data_push.bind(&"sparring.queue.update", payload),
		instance.name
	)


static func _names(peers: Array) -> Array:
	var ws: WorldServer = WorldServer.curr
	var out: Array = []
	if ws == null:
		return out
	for peer: int in peers:
		var pr: PlayerResource = ws.connected_players.get(peer)
		out.append(pr.display_name if pr != null else "?")
	return out


static func _on_fighter_left_zone(body: Node, key: String) -> void:
	if body is not Player:
		return
	var match_data: Dictionary = _matches.get(key, {})
	if match_data.is_empty():
		return
	var leaver: int = int((body as Player).player_resource.current_peer_id)
	if not (match_data["team_of"] as Dictionary).has(leaver):
		return
	# Leaving the arena = dying: out, and maybe their team is eliminated.
	(match_data["alive"] as Dictionary)[leaver] = false
	(body as Player).player_resource.in_match = false
	_peer_to_match.erase(leaver)
	_check_elimination(key)


static func _key(instance_name: String, master_id: int) -> String:
	return "%s::%d" % [instance_name, master_id]


## The station position for the match this player is in (where a dying fighter
## respawns). Vector2.ZERO if not resolvable. Called by Player.die BEFORE
## on_player_died_in_match, while the peer is still mapped.
static func return_position_for(player: Player) -> Vector2:
	if player == null or player.player_resource == null:
		return Vector2.ZERO
	var key: String = str(_peer_to_match.get(int(player.player_resource.current_peer_id), ""))
	if key.is_empty() or not _matches.has(key):
		return Vector2.ZERO
	var match_data: Dictionary = _matches[key]
	var ws: WorldServer = WorldServer.curr
	if ws == null or ws.instance_manager == null:
		return Vector2.ZERO
	var instance: Node = ws.instance_manager.get_instance_server_by_id(str(match_data["instance_name"]))
	if instance == null or instance.instance_map == null:
		return Vector2.ZERO
	var master: DuelMaster = instance.instance_map.get_duel_master(int(match_data["master_id"]))
	return master.global_position if master != null else Vector2.ZERO


## True if both players are ACTIVE fighters on the same team of the same match.
## Used by support effects (heal bolt) so "ally" means spar teammate while a
## match is live — and an outsider can't buff a fighter from the sidelines.
static func are_spar_teammates(a: Player, b: Player) -> bool:
	if a == null or b == null or a.player_resource == null or b.player_resource == null:
		return false
	var a_key: String = str(_peer_to_match.get(int(a.player_resource.current_peer_id), ""))
	if a_key.is_empty() or not _matches.has(a_key):
		return false
	if a_key != str(_peer_to_match.get(int(b.player_resource.current_peer_id), "")):
		return false
	var team_of: Dictionary = _matches[a_key]["team_of"]
	var a_peer: int = int(a.player_resource.current_peer_id)
	var b_peer: int = int(b.player_resource.current_peer_id)
	return team_of.has(a_peer) and team_of.has(b_peer) and team_of[a_peer] == team_of[b_peer]


## True if `source` may damage `target` via a live spar: same match, DIFFERENT
## teams (friendly fire off), and the countdown is over.
static func can_spar_damage(source: Player, target: Player) -> bool:
	if source == null or target == null or source.player_resource == null or target.player_resource == null:
		return false
	if not source.player_resource.in_match or not target.player_resource.in_match:
		return false
	var s_peer: int = int(source.player_resource.current_peer_id)
	var t_peer: int = int(target.player_resource.current_peer_id)
	var key: String = str(_peer_to_match.get(s_peer, ""))
	if key.is_empty() or key != str(_peer_to_match.get(t_peer, "")) or not _matches.has(key):
		return false
	var match_data: Dictionary = _matches[key]
	if Time.get_ticks_msec() < int(match_data.get("pvp_enabled_at_ms", 0)):
		return false
	var team_of: Dictionary = match_data["team_of"]
	return team_of.has(s_peer) and team_of.has(t_peer) and team_of[s_peer] != team_of[t_peer]
