class_name DungeonService
## Server-only orchestration of a dungeon RUN: form the co-op group, spin up a
## PRIVATE instance for it, move everyone in, and dissolve it on exit. Allegiance
## (groupmates = allies) comes from GroupService; this drives the instance
## lifecycle by reusing the warper travel (player_switch_instance) + instance
## charging.
##
## v1 SLICE: solo entry via the entrance portal (the lobby that forms a multi-
## player group calls the SAME start_run with the group's peers — next chunk).
## No timer / scaling / lockout / shadow-mob authoring yet — see docs/dungeons.md.
## Server-authoritative; common-side state with direct WorldServer access like SparringService.

# group_id -> the private dungeon ServerInstance (Node) running for that group.
static var _runs: Dictionary[int, Node] = {}
# private instance node name -> group_id, so an exit can find its run.
static var _instance_to_group: Dictionary[String, int] = {}
# lobby key (instance_name:master_id) -> Array[int] of queued peer ids.
static var _lobbies: Dictionary[String, Array] = {}
# group_id -> run start (ticks_msec), for the completion time in the recap.
static var _run_start_ms: Dictionary[int, int] = {}
# group_ids currently being auto-ejected after a CLEAR — so on_player_left can tell
# a voluntary leave (toast "Left X") from the post-clear eject (recap covers it).
static var _ejecting: Dictionary[int, bool] = {}
# group_id -> whether this run is HARD (scaled mobs, richer reward, separate lockout).
static var _run_hard: Dictionary[int, bool] = {}
# group_id -> shared revive pool left (HARD runs only). Each death spends one; the death that finds
# it empty FAILS the whole run. Sized one-per-member, or SOLO_REVIVES for a lone runner.
static var _run_revives: Dictionary[int, int] = {}

# Private ROOMS (the Browse tab) — pre-run lobbies a player creates + shares, kept
# alongside the implicit public queue. room_id -> { leader, members: Array[peer],
# hard, code, instance_name, master_id, dungeon: DungeonResource }.
static var _rooms: Dictionary[int, Dictionary] = {}
static var _code_to_room: Dictionary[String, int] = {}  # CODE -> room_id
static var _peer_to_room: Dictionary[int, int] = {}      # peer -> the room it's in
static var _next_room_id: int = 1
## Join-code: two digits — short + easy to share. Rerolls on collision, so it caps
## concurrent rooms under ~100 (fine at our scale; widen if that ever bites).
const ROOM_CODE_CHARS: String = "0123456789"
const ROOM_CODE_LEN: int = 2

const QUEUE_RANGE: float = 120.0
## Seconds the recap stays up before the party is auto-sent home.
const EJECT_DELAY_S: float = 15.0
## Seconds the "RUN FAILED" recap shows before a wiped party is sent home. Long enough to read the
## recap; kept > RESPAWN_DELAY so any teammate mid-death-countdown respawns before the eject.
const FAIL_EJECT_DELAY_S: float = 6.0
## Revives a SOLO hardcore run gets. A party run gets one per member instead (see start_run).
const SOLO_REVIVES: int = 4
## Hard-mode stat multipliers, applied to every mob a Hard run spawns.
const HARD_HEALTH_MULT: float = 2.0
const HARD_DAMAGE_MULT: float = 1.5


## Is the run living in [param instance] a Hard one? Read by RoomNode when it spawns
## mobs (to scale them) and picks the reward.
static func is_hard_run(instance: Node) -> bool:
	if instance == null:
		return false
	return _run_hard.get(_instance_to_group.get(str(instance.name), 0), false)


# --- lobby (matchmaking at a DungeonMaster station) -------------------------

## Join / leave / start / solo a dungeon lobby (dungeon.queue handler). Mirrors
## the spar queue, minus teams: one shared queue per station, Start launches the
## whole queue into a private run, Solo launches just the caller. Server-only.
static func handle_lobby_request(instance: Node, peer_id: int, station: String, action: String, hard: bool = false) -> Dictionary:
	var st: Dictionary = _resolve_station(instance, station)
	if st.is_empty():
		return {"ok": false, "reason": "no_dungeon"}
	var node: Node2D = st["node"]
	var dungeon: DungeonResource = st["dungeon"]
	var player: Player = instance.get_player(peer_id)
	if player == null:
		return {"ok": false, "reason": "no_player"}
	if player.global_position.distance_to(node.global_position) > QUEUE_RANGE:
		return {"ok": false, "reason": "too_far"}
	if GroupService.group_of(peer_id) != 0:
		return {"ok": false, "reason": "in_run"} # already inside a dungeon

	var key: String = _lobby_key(instance.name, station)
	var queue: Array = _lobbies.get(key, [])
	# Can't sit in the public queue AND a private room at once — taking a public
	# action drops any private room first.
	if action in ["join", "solo", "start"]:
		_leave_room(peer_id)
	match action:
		"leave":
			queue.erase(peer_id)
			_lobbies[key] = queue
			_broadcast_lobby(instance, station, dungeon, queue)
			return lobby_status(instance, peer_id, station)
		"join":
			if queue.size() >= dungeon.party_size:
				return {"ok": false, "reason": "full"}
			if not queue.has(peer_id):
				queue.append(peer_id)
			_lobbies[key] = queue
			_broadcast_lobby(instance, station, dungeon, queue)
			return lobby_status(instance, peer_id, station)
		"solo":
			queue.erase(peer_id)
			_lobbies[key] = queue
			_broadcast_lobby(instance, station, dungeon, queue)
			start_run([peer_id], dungeon, hard)
			return {"ok": true, "started": true}
		"start":
			# Launch the whole queue (or just the caller if the queue is empty).
			var party: Array = queue.duplicate()
			if not party.has(peer_id):
				party.append(peer_id)
			_lobbies.erase(key)
			_broadcast_lobby(instance, station, dungeon, [])
			start_run(party, dungeon, hard)
			return {"ok": true, "started": true}
		_:
			return {"ok": false, "reason": "bad_action"}


## Lobby snapshot for the caller (dungeon.info handler).
static func lobby_status(instance: Node, peer_id: int, station: String) -> Dictionary:
	var st: Dictionary = _resolve_station(instance, station)
	if st.is_empty():
		return {"ok": false, "reason": "no_dungeon"}
	var dungeon: DungeonResource = st["dungeon"]
	var queue: Array = _lobbies.get(_lobby_key(instance.name, station), [])
	return {
		"ok": true,
		"master_name": dungeon.title(),
		"capacity": dungeon.party_size,
		"members": _names(instance, queue),
		"queued": queue.has(peer_id),
		"started": false,
		"dungeon": _dungeon_info(dungeon),
	}


## Resolve a station by its node NAME → {node, dungeon}. Works for a legacy
## DungeonMaster (its .dungeon) or a dungeon-keeper NPC (its DungeonInteraction) —
## both are direct map children, so get_node(name) finds them. Empty if the node is
## gone or isn't a dungeon station. This is what replaces the manual master_id.
static func _resolve_station(instance: Node, station: String) -> Dictionary:
	if instance == null or instance.instance_map == null or station.is_empty():
		return {}
	var node: Node = instance.instance_map.get_node_or_null(NodePath(station))
	if node == null:
		return {}
	var dungeon: DungeonResource = _station_dungeon(node)
	if dungeon == null:
		return {}
	return {"node": node, "dungeon": dungeon}


static func _station_dungeon(node: Node) -> DungeonResource:
	if node is DungeonMaster:
		return (node as DungeonMaster).dungeon
	if node is NPC and (node as NPC).npc_resource != null:
		for inter: NPCInteraction in (node as NPC).npc_resource.interactions:
			if inter is DungeonInteraction:
				return (inter as DungeonInteraction).dungeon
	return null


## The dungeon's data for the manager UI (name/description/levels/reward summary),
## read off its DungeonResource. Falls back to bare defaults if it isn't one.
static func _dungeon_info(dres: DungeonResource) -> Dictionary:
	if dres == null:
		return {"name": "Dungeon", "description": "", "min_level": 0, "recommended_level": 0, "reward": "—", "hard_reward": "—"}
	return {
		"name": str(dres.instance_name),
		"description": dres.description,
		"min_level": dres.min_level,
		"recommended_level": dres.recommended_level,
		"reward": _reward_summary(dres.reward),
		"hard_reward": _reward_summary(dres.hard_reward),
	}


## A short human string for a DungeonReward: "50–120 gold, Iron Bar".
static func _reward_summary(reward: DungeonReward) -> String:
	if reward == null:
		return "—"
	var parts: PackedStringArray = PackedStringArray()
	if reward.gold_max > 0:
		if reward.gold_min == reward.gold_max:
			parts.append("%d gold" % reward.gold_max)
		else:
			parts.append("%d–%d gold" % [reward.gold_min, reward.gold_max])
	for drop: LootDrop in reward.loot:
		if drop != null and drop.item != null:
			parts.append(str(drop.item.item_name))
	return ", ".join(parts) if not parts.is_empty() else "—"


## Push the live roster to everyone in the queue (so they see joins/leaves).
static func _broadcast_lobby(instance: Node, station: String, dungeon: DungeonResource, queue: Array) -> void:
	if WorldServer.curr == null or dungeon == null:
		return
	var payload: Dictionary = {
		"station": station,
		"capacity": dungeon.party_size,
		"members": _names(instance, queue),
	}
	for peer: int in queue:
		WorldServer.curr.data_push.rpc_id(peer, &"dungeon.lobby.update", payload)


static func _names(instance: Node, peers: Array) -> Array:
	var out: Array = []
	for peer: int in peers:
		var player: Player = instance.get_player(peer)
		if player != null and player.player_resource != null:
			out.append(player.player_resource.display_name)
	return out


static func _lobby_key(instance_name: String, station: String) -> String:
	return "%s::%s" % [instance_name, station]


# --- private rooms (Browse tab) ---------------------------------------------

## list / create / join / join_code / leave / start a private room (dungeon.rooms
## handler). A room is a named pre-run lobby with a share code; the leader Starts
## it. Server-only.
static func handle_room_request(instance: Node, peer_id: int, station: String, action: String, args: Dictionary) -> Dictionary:
	var st: Dictionary = _resolve_station(instance, station)
	if st.is_empty():
		return {"ok": false, "reason": "no_dungeon"}
	var node: Node2D = st["node"]
	var dungeon: DungeonResource = st["dungeon"]
	var player: Player = instance.get_player(peer_id)
	if player == null:
		return {"ok": false, "reason": "no_player"}

	match action:
		"create":
			if player.global_position.distance_to(node.global_position) > QUEUE_RANGE:
				return {"ok": false, "reason": "too_far"}
			if GroupService.group_of(peer_id) != 0:
				return {"ok": false, "reason": "in_run"}
			_leave_room(peer_id) # only one room at a time
			var room_id: int = _next_room_id
			_next_room_id += 1
			var code: String = _gen_room_code()
			_rooms[room_id] = {
				"leader": peer_id, "members": [peer_id], "hard": bool(args.get("hard", false)),
				"code": code, "instance_name": str(instance.name), "station": station,
				"dungeon": dungeon,
			}
			_code_to_room[code] = room_id
			_peer_to_room[peer_id] = room_id
			_leave_public_queue(instance, peer_id, station) # one lobby at a time
			return {"ok": true, "room": _room_snapshot(instance, room_id, peer_id)}
		"join_code":
			return _join_room(instance, peer_id, _code_to_room.get(str(args.get("code", "")).strip_edges().to_upper(), 0), station)
		"leave":
			_leave_room(peer_id)
			return {"ok": true, "left": true}
		"start":
			return _start_room(peer_id)
		_:
			return {"ok": false, "reason": "bad_action"}


static func _join_room(instance: Node, peer_id: int, room_id: int, station: String) -> Dictionary:
	if not _rooms.has(room_id):
		return {"ok": false, "reason": "no_room"}
	if GroupService.group_of(peer_id) != 0:
		return {"ok": false, "reason": "in_run"}
	var room: Dictionary = _rooms[room_id]
	if str(room.get("station", "")) != station or str(room.get("instance_name", "")) != str(instance.name):
		return {"ok": false, "reason": "no_room"} # belongs to a different station
	var members: Array = room["members"]
	if members.size() >= (room["dungeon"] as DungeonResource).party_size:
		return {"ok": false, "reason": "full"}
	if not members.has(peer_id):
		_leave_room(peer_id)
		members.append(peer_id)
		_peer_to_room[peer_id] = room_id
		_leave_public_queue(instance, peer_id, station) # one lobby at a time
	_broadcast_room(room_id)
	return {"ok": true, "room": _room_snapshot(instance, room_id, peer_id)}


## Remove a peer from whatever room they're in. Leader leaving (or the last member)
## dissolves the room; otherwise the rest get a refreshed snapshot.
static func _leave_room(peer_id: int) -> void:
	var room_id: int = _peer_to_room.get(peer_id, 0)
	_peer_to_room.erase(peer_id)
	if room_id == 0 or not _rooms.has(room_id):
		return
	var room: Dictionary = _rooms[room_id]
	(room["members"] as Array).erase(peer_id)
	if int(room.get("leader", 0)) == peer_id or (room["members"] as Array).is_empty():
		_close_room(room_id, true)
	else:
		_broadcast_room(room_id)


## Drop a room. [param notify] pushes a "closed" update to its (former) members.
static func _close_room(room_id: int, notify: bool) -> void:
	if not _rooms.has(room_id):
		return
	var room: Dictionary = _rooms[room_id]
	var members: Array = (room["members"] as Array).duplicate()
	_code_to_room.erase(str(room.get("code", "")))
	_rooms.erase(room_id)
	for peer: int in members:
		_peer_to_room.erase(peer)
		if notify and WorldServer.curr != null:
			WorldServer.curr.data_push.rpc_id(peer, &"dungeon.room.update", {"closed": true})


static func _start_room(peer_id: int) -> Dictionary:
	var room_id: int = _peer_to_room.get(peer_id, 0)
	if room_id == 0 or not _rooms.has(room_id):
		return {"ok": false, "reason": "no_room"}
	var room: Dictionary = _rooms[room_id]
	if int(room.get("leader", 0)) != peer_id:
		return {"ok": false, "reason": "not_leader"}
	var members: Array = (room["members"] as Array).duplicate()
	var dungeon: DungeonResource = room["dungeon"]
	var hard: bool = bool(room.get("hard", false))
	# Tell the members (incl. waiting non-leaders) to close their menu, then launch.
	if WorldServer.curr != null:
		for peer: int in members:
			WorldServer.curr.data_push.rpc_id(peer, &"dungeon.room.update", {"started": true})
	_close_room(room_id, false)
	start_run(members, dungeon, hard)
	return {"ok": true, "started": true}


static func _broadcast_room(room_id: int) -> void:
	if not _rooms.has(room_id) or WorldServer.curr == null:
		return
	var room: Dictionary = _rooms[room_id]
	var instance: Node = WorldServer.curr.instance_manager.get_instance_server_by_id(str(room.get("instance_name", "")))
	if instance == null:
		return
	for peer: int in (room["members"] as Array):
		WorldServer.curr.data_push.rpc_id(peer, &"dungeon.room.update", _room_snapshot(instance, room_id, peer))


## Drop a peer from this station's public queue (called when they enter a private
## room — a player is in at most one lobby).
static func _leave_public_queue(instance: Node, peer_id: int, station: String) -> void:
	var key: String = _lobby_key(str(instance.name), station)
	if not _lobbies.has(key):
		return
	var queue: Array = _lobbies[key]
	if not queue.has(peer_id):
		return
	queue.erase(peer_id)
	_lobbies[key] = queue
	var st: Dictionary = _resolve_station(instance, station)
	if not st.is_empty():
		_broadcast_lobby(instance, station, st["dungeon"], queue)


## Per-member view of a room they're in.
static func _room_snapshot(instance: Node, room_id: int, viewer_peer: int) -> Dictionary:
	var room: Dictionary = _rooms[room_id]
	return {
		"room_id": room_id,
		"code": str(room.get("code", "")),
		"hard": bool(room.get("hard", false)),
		"is_leader": int(room.get("leader", 0)) == viewer_peer,
		"capacity": (room["dungeon"] as DungeonResource).party_size,
		"members": _names(instance, room["members"]),
	}


static func _gen_room_code() -> String:
	for _attempt: int in 24:
		var code: String = ""
		for _i: int in ROOM_CODE_LEN:
			code += ROOM_CODE_CHARS[randi() % ROOM_CODE_CHARS.length()]
		if not _code_to_room.has(code):
			return code
	return "R%d" % _next_room_id # fallback, effectively never hit


## Begin a run for [param peers] (solo = one peer; the lobby passes a full group).
## Charges a FRESH private instance of [param dungeon_name] — NOT the shared
## charged copy — and moves the group in once it's loaded. Server-only.
static func start_run(peers: Array, dungeon: DungeonResource, hard: bool = false) -> void:
	if WorldServer.curr == null or peers.is_empty() or dungeon == null:
		return
	var instance_manager: Node = WorldServer.curr.instance_manager
	var members: Array = []
	for p: Variant in peers:
		if int(p) > 0:
			members.append(int(p))
	if members.is_empty():
		return
	var group_id: int = GroupService.create_group(members, members[0])
	_run_start_ms[group_id] = Time.get_ticks_msec()
	_run_hard[group_id] = hard
	# Hardcore: a shared revive pool — one per party member, or SOLO_REVIVES for a lone runner.
	if hard:
		_run_revives[group_id] = SOLO_REVIVES if members.size() <= 1 else members.size()
	# Private instance: prepare a fresh one directly. We can't use
	# queue_charge_instance — it dedupes by resource, but every group needs its
	# OWN copy. prepare_instance appends it to charged_instances on ready, and
	# unload_unused_instances reclaims it once the group has all left.
	var instance: Node = instance_manager.prepare_instance(dungeon)
	_runs[group_id] = instance
	_instance_to_group[str(instance.name)] = group_id
	instance.ready.connect(func() -> void: _enter_run(group_id, members), CONNECT_ONE_SHOT)
	instance_manager.add_child(instance, true)


## Once the private instance is loaded, switch every group member in (from
## whatever instance they're standing in). Mob spawning is NOT done here anymore —
## the map's authored RoomNodes drive the encounters as the party walks in.
static func _enter_run(group_id: int, members: Array) -> void:
	var instance: Node = _runs.get(group_id, null)
	if instance == null or WorldServer.curr == null:
		return
	var instance_manager: Node = WorldServer.curr.instance_manager
	for peer: int in members:
		var current: Node = instance_manager.find_instance_for_peer(peer)
		if current == null:
			continue
		var player: Player = current.get_player(peer) as Player
		if player != null:
			instance_manager.player_switch_instance(instance, 0, player, current)
			player.restore_full() # enter a run topped up (HP + mana), spar-style — saves potions

	# Welcome toast — delayed so it lands after the client finishes loading the new
	# instance (the switch is still in flight this frame). Soft entry, not a wall of
	# mobs out of nowhere.
	var dungeon_name: String = "the dungeon"
	if instance.instance_resource != null:
		dungeon_name = str(instance.instance_resource.instance_name)
	WorldServer.curr.get_tree().create_timer(1.5).timeout.connect(
		func() -> void:
			for peer: int in GroupService.members_of(group_id):
				WorldServer.curr.data_push.rpc_id(peer, &"dungeon.entered", {"dungeon": dungeon_name})
			_push_hud(group_id),
		CONNECT_ONE_SHOT
	)


## A player left a dungeon-run instance (exit warp, or any switch out of it). Drop
## them from the run; when the run empties, dissolve the group — the now-empty
## private instance is then collected by unload_unused_instances. No-op for a
## switch out of any non-dungeon instance. Server-only.
static func on_player_left(peer_id: int, left_instance: Node) -> void:
	if left_instance == null:
		return
	var key: String = str(left_instance.name)
	var group_id: int = _instance_to_group.get(key, 0)
	if group_id == 0:
		return # not a dungeon run — ordinary warp/recall/jail
	# Confirm a VOLUNTARY leave (exit NPC / recall). The post-clear auto-eject is
	# flagged in _ejecting and skipped here — its recap already says it all.
	if not _ejecting.get(group_id, false) and WorldServer.curr != null:
		var dungeon_name: String = "the dungeon"
		if left_instance.instance_resource != null:
			dungeon_name = str(left_instance.instance_resource.instance_name)
		WorldServer.curr.data_push.rpc_id(peer_id, &"dungeon.left", {"dungeon": dungeon_name})
	if WorldServer.curr != null:
		WorldServer.curr.data_push.rpc_id(peer_id, &"dungeon.hud", {"active": false}) # leaver's HUD off
	GroupService.leave(peer_id)
	if GroupService.members_of(group_id).is_empty():
		_runs.erase(group_id)
		_instance_to_group.erase(key)
		_run_start_ms.erase(group_id)
		_ejecting.erase(group_id)
		_run_hard.erase(group_id)
		_run_revives.erase(group_id)


## The final room cleared — the run is COMPLETE. Grant each member their reward
## (honoring the soft daily lockout), push a per-member recap (dungeon name,
## completion time, what they got), then after EJECT_DELAY_S send everyone home and
## let the group dissolve. Called from RoomNode (final_room). Server-only.
static func on_dungeon_cleared(instance: Node) -> void:
	if instance == null or WorldServer.curr == null:
		return
	var group_id: int = _instance_to_group.get(str(instance.name), 0)
	if group_id == 0:
		return
	_hide_hud(group_id) # the run clock stops on clear; the recap shows the final time
	var start_ms: int = _run_start_ms.get(group_id, Time.get_ticks_msec())
	var seconds: int = int((Time.get_ticks_msec() - start_ms) / 1000.0)
	var hard: bool = _run_hard.get(group_id, false)
	var dungeon_name: String = "Dungeon"
	if instance.instance_resource != null:
		dungeon_name = str(instance.instance_resource.instance_name)
	# The completion reward lives on the dungeon's DungeonResource; pick Normal vs
	# Hard here (Hard falls back to the normal reward if none authored).
	var dres: DungeonResource = instance.instance_resource as DungeonResource
	var reward: DungeonReward = null
	if dres != null:
		reward = dres.hard_reward if (hard and dres.hard_reward != null) else dres.reward
	# Hard runs get a separate daily lockout (clear Normal AND Hard each per day) and
	# a tagged recap label.
	var lockout_key: String = dungeon_name + (" (Hard)" if hard else "")
	var label: String = dungeon_name + (" — Hard" if hard else "")
	for peer: int in GroupService.members_of(group_id):
		var player: Player = instance.get_player(peer) as Player # all members are in this run
		# Only HARD clears are ranked — the fixed hand-designed course is the fair
		# race (Normal will go procedural later). The time stands apart from the
		# reward lockout, so a reward-locked re-run can still set a faster record.
		if hard and player != null:
			LeaderboardService.record_dungeon_clear(player, dungeon_name, seconds)
		WorldServer.curr.data_push.rpc_id(peer, &"dungeon.cleared", {
			"dungeon": label,
			"seconds": seconds,
			"eject_in": int(EJECT_DELAY_S),
			"reward": _grant_reward(player, lockout_key, reward),
		})
	# (The victory sting is fired by the dungeon boss's own BossController on death.)
	# Linger on the recap, then send the party home; on_player_left dissolves the
	# group as each one leaves.
	WorldServer.curr.get_tree().create_timer(EJECT_DELAY_S).timeout.connect(
		func() -> void: _eject_run(group_id), CONNECT_ONE_SHOT
	)


## Grant one player their completion reward, honoring the soft daily lockout, and
## return the recap summary for their client: {gold, items:[{name, amount}]} on a
## payout, or {locked: true, available_in: <seconds>} if they already collected it
## within the window. Items land in their (server-authoritative) inventory; the
## client sees them on its next inventory.get — same as mob loot.
static func _grant_reward(player: Player, lockout_key: String, reward: DungeonReward) -> Dictionary:
	if player == null or player.player_resource == null or reward == null:
		return {}
	var resource: PlayerResource = player.player_resource
	var now_s: int = int(Time.get_unix_time_from_system())
	var window_s: int = int(reward.lockout_hours * 3600.0)
	var last_s: int = int(resource.dungeon_lockouts.get(lockout_key, 0))
	if window_s > 0 and now_s - last_s < window_s:
		return {"locked": true, "available_in": window_s - (now_s - last_s)}

	var gold: int = 0
	if reward.gold_max > 0:
		gold = randi_range(reward.gold_min, reward.gold_max)
		if gold > 0 and Economy.gold_id() > 0:
			Inventory.add_item(resource.inventory, Economy.gold_id(), gold)

	var items: Array = []
	for drop: LootDrop in reward.loot:
		if drop == null or drop.item == null:
			continue
		if randf() <= drop.chance:
			var amount: int = randi_range(drop.min_amount, drop.max_amount)
			if amount > 0:
				Inventory.add_item(resource.inventory, int(drop.item.get_meta(&"id", 0)), amount)
				items.append({"name": str(drop.item.item_name), "amount": amount})

	resource.dungeon_lockouts[lockout_key] = now_s
	return {"gold": gold, "items": items}


## A player died inside a run. HARD runs draw from a shared revive pool: spend one and respawn as
## usual, or — if it's already empty — FAIL the run (the whole party is revived + sent home, no
## reward). Returns true if the run FAILED, so the caller (Player.die) skips its normal respawn.
## Normal runs and non-dungeon deaths return false (respawn freely). Server-only.
static func register_dungeon_death(player: Node) -> bool:
	if player == null or player.player_resource == null:
		return false
	var group_id: int = GroupService.group_of(int(player.player_resource.current_peer_id))
	if group_id == 0 or not _runs.has(group_id) or not _run_hard.get(group_id, false):
		return false # not a hardcore dungeon run — free respawn
	var revives: int = _run_revives.get(group_id, 0)
	if revives > 0:
		_run_revives[group_id] = revives - 1
		var left: int = revives - 1
		_notify_party(group_id, "A hero has fallen — %d revive%s left." % [left, "" if left == 1 else "s"])
		_push_hud(group_id) # refresh the HUD revive count for the party
		return false # respawn at the dungeon entrance as usual
	_fail_run(group_id)
	return true # pool exhausted — run over


## The revive pool is spent and someone died: the run FAILS. Revive everyone (so they arrive home
## alive), tell them, then eject to town after a short beat. No reward. Server-only.
static func _fail_run(group_id: int) -> void:
	if WorldServer.curr == null or _ejecting.get(group_id, false):
		return
	_ejecting[group_id] = true # mark the eject non-voluntary (no "Left X" toast in on_player_left)
	_hide_hud(group_id) # stop the run clock immediately, ahead of the eject delay
	var instance: Node = _runs.get(group_id, null)
	var dungeon_name: String = "the dungeon"
	if instance != null and instance.instance_resource != null:
		dungeon_name = str(instance.instance_resource.instance_name)
	var seconds: int = int(_elapsed_s(group_id)) # how long the party survived, for the recap
	for peer: int in GroupService.members_of(group_id):
		var player: Player = null
		if instance != null:
			player = instance.get_player(peer) as Player
		if player != null:
			player.revive() # arrive home alive, not a corpse
		WorldServer.curr.data_push.rpc_id(peer, &"dungeon.failed", {"failed": true, "dungeon": dungeon_name, "seconds": seconds, "eject_in": int(FAIL_EJECT_DELAY_S)})
	_notify_party(group_id, "The party has fallen — the run failed. Returning to town…")
	WorldServer.curr.get_tree().create_timer(FAIL_EJECT_DELAY_S).timeout.connect(
		func() -> void: _eject_run(group_id), CONNECT_ONE_SHOT
	)


## A system chat line to every member still in the run (revive count, run-failed notice).
static func _notify_party(group_id: int, message: String) -> void:
	if WorldServer.curr == null:
		return
	var instance: Node = _runs.get(group_id, null)
	if instance == null:
		return
	for peer: int in GroupService.members_of(group_id):
		var player: Player = instance.get_player(peer) as Player
		if player != null and player.player_resource != null:
			WorldServer.curr.chat_service.push_system_to_player(instance, player.player_resource.player_id, message)


## Push the live run HUD (clock baseline + revive count) to every member. has_pool=false on a Normal
## run, so the client shows just the clock.
static func _push_hud(group_id: int) -> void:
	if WorldServer.curr == null:
		return
	var payload: Dictionary = {
		"active": true,
		"elapsed_s": _elapsed_s(group_id),
		"has_pool": _run_hard.get(group_id, false),
		"revives": _run_revives.get(group_id, 0),
	}
	for peer: int in GroupService.members_of(group_id):
		WorldServer.curr.data_push.rpc_id(peer, &"dungeon.hud", payload)


## Tell every member to hide the run HUD (the run cleared or failed).
static func _hide_hud(group_id: int) -> void:
	if WorldServer.curr == null:
		return
	for peer: int in GroupService.members_of(group_id):
		WorldServer.curr.data_push.rpc_id(peer, &"dungeon.hud", {"active": false})


## Seconds since this run began (server clock) — the HUD clock baseline.
static func _elapsed_s(group_id: int) -> float:
	var start_ms: int = _run_start_ms.get(group_id, Time.get_ticks_msec())
	return float(Time.get_ticks_msec() - start_ms) / 1000.0


## Sweep a disconnecting peer out of any dungeon lobby queue AND out of a live run
## (dissolving the group when it empties), mirroring SparringService. Without this
## a mid-run crash leaves a phantom in the group/lobby and a never-freed run map.
## Wired from WorldServer._on_peer_disconnected.
static func on_peer_disconnected(peer_id: int) -> void:
	var ws: WorldServer = WorldServer.curr
	_leave_room(peer_id) # pending private room, if any
	# Lobby queues — drop them and refresh the remaining queuers' rosters.
	for key: String in _lobbies.keys():
		var queue: Array = _lobbies[key]
		if not queue.has(peer_id):
			continue
		queue.erase(peer_id)
		_lobbies[key] = queue
		if ws != null:
			var parts: PackedStringArray = key.rsplit("::", true, 1) # "instance::station"
			if parts.size() == 2:
				var instance: Node = ws.instance_manager.get_instance_server_by_id(parts[0])
				if instance != null and instance.instance_map != null:
					var st: Dictionary = _resolve_station(instance, parts[1])
					if not st.is_empty():
						_broadcast_lobby(instance, parts[1], st["dungeon"], queue)
	# Live run — leave the group; when it empties, drop the run bookkeeping (the
	# now-empty private instance is reclaimed by unload_unused_instances). No
	# "Left X" toast — they're gone.
	var group_id: int = GroupService.group_of(peer_id)
	if group_id != 0 and _runs.has(group_id):
		GroupService.leave(peer_id)
		if GroupService.members_of(group_id).is_empty():
			var inst: Node = _runs.get(group_id)
			if inst != null:
				_instance_to_group.erase(str(inst.name))
			_runs.erase(group_id)
			_run_start_ms.erase(group_id)
			_ejecting.erase(group_id)
			_run_hard.erase(group_id)
			_run_revives.erase(group_id)


static func _eject_run(group_id: int) -> void:
	if WorldServer.curr == null:
		return
	_ejecting[group_id] = true # this leave is the cleared eject, not a voluntary bail
	var instance_manager: Node = WorldServer.curr.instance_manager
	var instance: Node = _runs.get(group_id, null)
	for peer: int in GroupService.members_of(group_id).duplicate():
		if instance != null: # leave the run topped up (HP + mana), symmetric with the entry refill
			var player: Player = instance.get_player(peer) as Player
			if player != null:
				player.restore_full()
		instance_manager.recall_player(peer) # → town hub; on_player_left dissolves the group
