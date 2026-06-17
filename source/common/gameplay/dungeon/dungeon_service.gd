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
## Server-authoritative; common-side state via ServerHub like SparringService.

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

const QUEUE_RANGE: float = 120.0
## Seconds the recap stays up before the party is auto-sent home.
const EJECT_DELAY_S: float = 15.0
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
static func handle_lobby_request(instance: Node, peer_id: int, master_id: int, action: String, hard: bool = false) -> Dictionary:
	if instance == null or instance.instance_map == null:
		return {"ok": false, "reason": "no_map"}
	var master: DungeonMaster = instance.instance_map.get_dungeon_master(master_id)
	if master == null:
		return {"ok": false, "reason": "no_master"}
	var player: Player = instance.get_player(peer_id)
	if player == null:
		return {"ok": false, "reason": "no_player"}
	if player.global_position.distance_to(master.global_position) > QUEUE_RANGE:
		return {"ok": false, "reason": "too_far"}
	if GroupService.group_of(peer_id) != 0:
		return {"ok": false, "reason": "in_run"} # already inside a dungeon

	var key: String = _lobby_key(instance.name, master_id)
	var queue: Array = _lobbies.get(key, [])
	match action:
		"leave":
			queue.erase(peer_id)
			_lobbies[key] = queue
			_broadcast_lobby(instance, master, queue)
			return lobby_status(instance, peer_id, master_id)
		"join":
			if queue.size() >= master.party_size:
				return {"ok": false, "reason": "full"}
			if not queue.has(peer_id):
				queue.append(peer_id)
			_lobbies[key] = queue
			_broadcast_lobby(instance, master, queue)
			return lobby_status(instance, peer_id, master_id)
		"solo":
			queue.erase(peer_id)
			_lobbies[key] = queue
			_broadcast_lobby(instance, master, queue)
			start_run([peer_id], master.dungeon_name, hard)
			return {"ok": true, "started": true}
		"start":
			# Launch the whole queue (or just the caller if the queue is empty).
			var party: Array = queue.duplicate()
			if not party.has(peer_id):
				party.append(peer_id)
			_lobbies.erase(key)
			_broadcast_lobby(instance, master, [])
			start_run(party, master.dungeon_name, hard)
			return {"ok": true, "started": true}
		_:
			return {"ok": false, "reason": "bad_action"}


## Lobby snapshot for the caller (dungeon.info handler).
static func lobby_status(instance: Node, peer_id: int, master_id: int) -> Dictionary:
	if instance == null or instance.instance_map == null:
		return {"ok": false, "reason": "no_map"}
	var master: DungeonMaster = instance.instance_map.get_dungeon_master(master_id)
	if master == null:
		return {"ok": false, "reason": "no_master"}
	var queue: Array = _lobbies.get(_lobby_key(instance.name, master_id), [])
	return {
		"ok": true,
		"master_name": master.master_name,
		"capacity": master.party_size,
		"members": _names(instance, queue),
		"queued": queue.has(peer_id),
		"started": false,
	}


## Push the live roster to everyone in the queue (so they see joins/leaves).
static func _broadcast_lobby(instance: Node, master: DungeonMaster, queue: Array) -> void:
	if ServerHub.current == null:
		return
	var payload: Dictionary = {
		"master_id": master.master_id,
		"capacity": master.party_size,
		"members": _names(instance, queue),
	}
	for peer: int in queue:
		ServerHub.current.data_push.rpc_id(peer, &"dungeon.lobby.update", payload)


static func _names(instance: Node, peers: Array) -> Array:
	var out: Array = []
	for peer: int in peers:
		var player: Player = instance.get_player(peer)
		if player != null and player.player_resource != null:
			out.append(player.player_resource.display_name)
	return out


static func _lobby_key(instance_name: String, master_id: int) -> String:
	return "%s:%d" % [instance_name, master_id]


## Begin a run for [param peers] (solo = one peer; the lobby passes a full group).
## Charges a FRESH private instance of [param dungeon_name] — NOT the shared
## charged copy — and moves the group in once it's loaded. Server-only.
static func start_run(peers: Array, dungeon_name: String, hard: bool = false) -> void:
	if ServerHub.current == null or peers.is_empty():
		return
	var instance_manager: Node = ServerHub.current.instance_manager
	var resource: Resource = instance_manager.instance_collection.get(dungeon_name, null)
	if resource == null:
		return
	var members: Array = []
	for p: Variant in peers:
		if int(p) > 0:
			members.append(int(p))
	if members.is_empty():
		return
	var group_id: int = GroupService.create_group(members, members[0])
	_run_start_ms[group_id] = Time.get_ticks_msec()
	_run_hard[group_id] = hard
	# Private instance: prepare a fresh one directly. We can't use
	# queue_charge_instance — it dedupes by resource, but every group needs its
	# OWN copy. prepare_instance appends it to charged_instances on ready, and
	# unload_unused_instances reclaims it once the group has all left.
	var instance: Node = instance_manager.prepare_instance(resource)
	_runs[group_id] = instance
	_instance_to_group[str(instance.name)] = group_id
	instance.ready.connect(func() -> void: _enter_run(group_id, members), CONNECT_ONE_SHOT)
	instance_manager.add_child(instance, true)


## Once the private instance is loaded, switch every group member in (from
## whatever instance they're standing in). Mob spawning is NOT done here anymore —
## the map's authored RoomNodes drive the encounters as the party walks in.
static func _enter_run(group_id: int, members: Array) -> void:
	var instance: Node = _runs.get(group_id, null)
	if instance == null or ServerHub.current == null:
		return
	var instance_manager: Node = ServerHub.current.instance_manager
	for peer: int in members:
		var current: Node = instance_manager.find_instance_for_peer(peer)
		if current == null:
			continue
		var player: Player = current.get_player(peer) as Player
		if player != null:
			instance_manager.player_switch_instance(instance, 0, player, current)

	# Welcome toast — delayed so it lands after the client finishes loading the new
	# instance (the switch is still in flight this frame). Soft entry, not a wall of
	# mobs out of nowhere.
	var dungeon_name: String = "the dungeon"
	if instance.instance_resource != null:
		dungeon_name = str(instance.instance_resource.instance_name)
	ServerHub.current.get_tree().create_timer(1.5).timeout.connect(
		func() -> void:
			for peer: int in GroupService.members_of(group_id):
				ServerHub.current.data_push.rpc_id(peer, &"dungeon.entered", {"dungeon": dungeon_name}),
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
	if not _ejecting.get(group_id, false) and ServerHub.current != null:
		var dungeon_name: String = "the dungeon"
		if left_instance.instance_resource != null:
			dungeon_name = str(left_instance.instance_resource.instance_name)
		ServerHub.current.data_push.rpc_id(peer_id, &"dungeon.left", {"dungeon": dungeon_name})
	GroupService.leave(peer_id)
	if GroupService.members_of(group_id).is_empty():
		_runs.erase(group_id)
		_instance_to_group.erase(key)
		_run_start_ms.erase(group_id)
		_ejecting.erase(group_id)
		_run_hard.erase(group_id)


## The final room cleared — the run is COMPLETE. Grant each member their reward
## (honoring the soft daily lockout), push a per-member recap (dungeon name,
## completion time, what they got), then after EJECT_DELAY_S send everyone home and
## let the group dissolve. Called from RoomNode (final_room). Server-only.
static func on_dungeon_cleared(instance: Node, reward: DungeonReward = null) -> void:
	if instance == null or ServerHub.current == null:
		return
	var group_id: int = _instance_to_group.get(str(instance.name), 0)
	if group_id == 0:
		return
	var start_ms: int = _run_start_ms.get(group_id, Time.get_ticks_msec())
	var seconds: int = int((Time.get_ticks_msec() - start_ms) / 1000.0)
	var hard: bool = _run_hard.get(group_id, false)
	var dungeon_name: String = "Dungeon"
	if instance.instance_resource != null:
		dungeon_name = str(instance.instance_resource.instance_name)
	# Hard runs get a separate daily lockout (clear Normal AND Hard each per day) and
	# a tagged recap label.
	var lockout_key: String = dungeon_name + (" (Hard)" if hard else "")
	var label: String = dungeon_name + (" — Hard" if hard else "")
	for peer: int in GroupService.members_of(group_id):
		var player: Player = instance.get_player(peer) as Player # all members are in this run
		ServerHub.current.data_push.rpc_id(peer, &"dungeon.cleared", {
			"dungeon": label,
			"seconds": seconds,
			"eject_in": int(EJECT_DELAY_S),
			"reward": _grant_reward(player, lockout_key, reward),
		})
	# Linger on the recap, then send the party home; on_player_left dissolves the
	# group as each one leaves.
	ServerHub.current.get_tree().create_timer(EJECT_DELAY_S).timeout.connect(
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


static func _eject_run(group_id: int) -> void:
	if ServerHub.current == null:
		return
	_ejecting[group_id] = true # this leave is the cleared eject, not a voluntary bail
	var instance_manager: Node = ServerHub.current.instance_manager
	for peer: int in GroupService.members_of(group_id).duplicate():
		instance_manager.recall_player(peer) # → town hub; on_player_left dissolves the group
