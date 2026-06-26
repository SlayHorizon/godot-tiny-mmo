class_name InstanceClient
extends Node


const LOCAL_PLAYER: PackedScene = preload("res://source/client/local_player/local_player.tscn")
const DUMMY_PLAYER: PackedScene = preload("res://source/common/gameplay/characters/player/player.tscn")
const FLOATING_DAMAGE_NUMBER: PackedScene = preload("res://source/client/ui/combat_feedback/floating_damage_number.tscn")

static var current: InstanceClient
static var local_player: LocalPlayer

var players_by_peer_id: Dictionary[int, Player]

var synchronizer_manager: StateSynchronizerManagerClient
var instance_map: Map


## Static dispatchers — called via the singleton subscriptions wired below.
## They look up the LIVE InstanceClient via [member current] every time,
## so we never hold a callable bound to a freed-instance `self`. That was
## the root cause of "I shoot but see no arrow after switching maps": the
## old per-instance subscription stayed in Client's subscriber list with
## a stale `self`, so the local visual path silently no-op'd.
static func _on_action_performed(payload: Dictionary) -> void:
	if current == null:
		return
	if payload.is_empty() or not payload.has_all(["p", "d", "i"]):
		return
	var player: Player = current.players_by_peer_id.get(payload["p"])
	if not player:
		return
	if player.equipment_component.mounted_nodes.has(&"weapon"):
		player.equipment_component.mounted_nodes[&"weapon"].perform_action(
			payload["i"], payload["d"], bool(payload.get("r", false))
		)


static func _on_combat_hit_static(payload: Dictionary) -> void:
	if current == null:
		return
	current._on_combat_hit(payload)


## A channel started somewhere nearby — attach its cast aura to the casting
## player (every client, so you see allies/enemies channel too). The local
## caster's root + move-cancel is handled separately in LocalPlayer.
static func _on_channel_start(payload: Dictionary) -> void:
	if current == null:
		return
	var player: Player = current.players_by_peer_id.get(int(payload.get("p", 0)), null)
	if player == null:
		return
	var existing: Node = player.get_node_or_null(^"ChannelVisual")
	if existing != null:
		existing.queue_free()
	var visual: ChannelVisual = ChannelVisual.new()
	visual.name = "ChannelVisual"
	visual.duration = float(payload.get("d", 6.0))
	visual.radius = float(payload.get("r", 60.0))
	visual.kind = StringName(payload.get("k", &"heal_aura"))
	player.add_child(visual)
	# The wielded weapon strikes its channel stance (the hammer plants + floats).
	# Recall isn't a weapon channel, so the weapon stays neutral for it.
	if StringName(payload.get("k", &"heal_aura")) != &"recall":
		var weapon: Weapon = player.equipment_component.mounted_nodes.get(&"weapon", null) as Weapon
		if weapon != null:
			weapon.set_channeling_pose(true)


## Channel ended (completed, cancelled, caster died) — drop the aura.
static func _on_channel_end(payload: Dictionary) -> void:
	if current == null:
		return
	var player: Player = current.players_by_peer_id.get(int(payload.get("p", 0)), null)
	if player == null:
		return
	var visual: Node = player.get_node_or_null(^"ChannelVisual")
	if visual != null:
		visual.queue_free()
	var weapon: Weapon = player.equipment_component.mounted_nodes.get(&"weapon", null) as Weapon
	if weapon != null:
		weapon.set_channeling_pose(false)


## A dungeon room sealed or opened — toggle its doors on every client. Movement is
## client-authoritative, so the collision change must happen here, not on the
## server. The push carries the door node paths (relative to the map); the server
## picks which doors. (The doors are authored into the map, so they already exist
## on the client — we just flip them.)
static func _on_dungeon_room(payload: Dictionary) -> void:
	if current == null or current.instance_map == null:
		return
	var is_open: bool = not bool(payload.get("sealed", false))
	for door_path: String in payload.get("doors", []):
		var door: Node = current.instance_map.get_node_or_null(NodePath(door_path))
		if door != null and door.has_method(&"set_open"):
			door.set_open(is_open)


## Left a dungeon run (exit NPC or recall) — confirm it. Subscribed statically so
## the push lands even mid instance-switch (a per-instance node would be torn down).
static func _on_dungeon_left(payload: Dictionary) -> void:
	Toaster.toast("Left %s." % str(payload.get("dungeon", "the dungeon")))


## Guard so we only subscribe ONCE per process — Client lives in the
## autoload and outlives any InstanceClient, so re-subscribing on every
## instance switch would either pile up callables or churn unsubscribe
## races against in-flight RPCs.
static var _subscribed: bool = false


func _ready() -> void:
	current = self
	if not _subscribed:
		Client.subscribe(&"action.perform", _on_action_performed)
		Client.subscribe(&"combat.hit", _on_combat_hit_static)
		Client.subscribe(&"channel.start", _on_channel_start)
		Client.subscribe(&"channel.end", _on_channel_end)
		Client.subscribe(&"dungeon.room", _on_dungeon_room)
		Client.subscribe(&"dungeon.left", _on_dungeon_left)
		_subscribed = true

	synchronizer_manager = StateSynchronizerManagerClient.new()
	synchronizer_manager.name = "StateSynchronizerManager"

	if instance_map.replicated_props_container:
		synchronizer_manager.add_container(1_000_000, instance_map.replicated_props_container)

	add_child(synchronizer_manager, true)


@rpc("any_peer", "call_remote", "reliable", 0)
func ready_to_enter_instance() -> void:
	pass


#region spawn/despawn
@rpc("authority", "call_remote", "reliable", 0)
func spawn_player(player_id: int) -> void:
	var new_player: Player
	
	if player_id == multiplayer.get_unique_id():
		# Reuse local player if already exists.
		if local_player and is_instance_valid(local_player):
			new_player = local_player
		else:
			new_player = LOCAL_PLAYER.instantiate() as LocalPlayer
			local_player = new_player

		# Always update instance and sync manager references.
		local_player.synchronizer_manager = synchronizer_manager
	else:
		new_player = DUMMY_PLAYER.instantiate()
	
	new_player.name = str(player_id)
	
	players_by_peer_id[player_id] = new_player
	
	if not new_player.is_inside_tree():
		instance_map.add_child(new_player)
		# Click-to-inspect: the player scene carries a ClickableArea (ProfileClickArea).
		# Wire its `clicked` to open the profile — the GATE (holster-mode) lives in the
		# handler, in CLIENT code, because Player.gd must not reference ClientState (cycle).
		# Connect once: the local player node is reused across map changes.
		if not new_player.has_meta(&"profile_click_wired"):
			new_player.set_meta(&"profile_click_wired", true)
			var click_area: ClickableArea = new_player.get_node_or_null(^"ProfileClickArea") as ClickableArea
			if click_area != null:
				click_area.clicked.connect(_on_player_clicked.bind(player_id))

	var sync: StateSynchronizer = new_player.state_synchronizer
	synchronizer_manager.add_entity(player_id, sync)


## A player's ClickableArea (ProfileClickArea) was clicked → open their profile, but ONLY
## while the local player has no weapon out (holster-mode), so a click during a fight
## stays a shot. [param peer_id] is sent to the server, which resolves it to the
## persistent player_id (the client doesn't carry it).
func _on_player_clicked(peer_id: int) -> void:
	var lp: LocalPlayer = ClientState.local_player
	if lp != null and is_instance_valid(lp) and not lp.is_armed():
		ClientState.player_profile_by_peer_requested.emit(peer_id)


func _on_combat_hit(payload: Dictionary) -> void:
	if payload.is_empty() or instance_map == null:
		return
	var amount: int = int(payload.get("amount", 0))
	if amount <= 0:
		return
	var pos_v: Variant = payload.get("position", Vector2.ZERO)
	var pos: Vector2 = pos_v if pos_v is Vector2 else Vector2.ZERO
	var number: FloatingDamageNumber = FLOATING_DAMAGE_NUMBER.instantiate()
	number.set_amount(amount, bool(payload.get("heal", false)))
	# Hand spawn position to the node BEFORE add_child so its _ready (which
	# fires synchronously during add_child) can seed its tween against the
	# real position instead of (0,0).
	number.set_spawn(pos)
	instance_map.add_child(number)


@rpc("authority", "call_remote", "reliable", 0)
func despawn_player(player_id: int) -> void:
	synchronizer_manager.remove_entity(player_id)
	
	var player: Player = players_by_peer_id.get(player_id, null)
	if player and player != local_player:
		player.queue_free()
	players_by_peer_id.erase(player_id)
#endregion
