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
	var kind: StringName = StringName(payload.get("k", &"heal_aura"))
	# A spin (Whirlwind) shows OVERLAPPING slashes (SpinVisual) blended into a
	# continuous sweep, not the drawn ring — and the weapon doesn't plant.
	if kind == &"spin":
		var radius: float = float(payload.get("r", 60.0))
		var slash: SpriteFrames = load("res://source/common/gameplay/combat/vfx/slash.tres") as SpriteFrames
		var spin: SpinVisual = SpinVisual.new()
		spin.name = "ChannelVisual"  # so channel.end frees it (and its in-flight slashes)
		spin.frames = slash
		spin.vfx_scale = radius / 64.0
		player.add_child(spin)
		return
	# Lightning Lash: a looping lightning beam that tracks your live aim (LashVisual), so it
	# sweeps with the cursor and shows roughly where the damage hitbox fires.
	if kind == &"siphon":
		# Life Siphon: the blood drain beam (same live-aim sweep as the lash; 128px frames).
		var drain: SpriteFrames = load("res://source/common/gameplay/combat/vfx/siphon_beam.tres") as SpriteFrames
		if drain != null:
			LashVisual.make(player, drain, float(payload.get("r", 100.0)), 128.0)
		return
	if kind == &"lash":
		var beam: SpriteFrames = load("res://source/common/gameplay/combat/vfx/lash_beam.tres") as SpriteFrames
		if beam != null:
			LashVisual.make(player, beam, float(payload.get("r", 120.0)))
		# A burst when the beam fires (the cast's "go" — the sky-strike just landed).
		var burst: SpriteFrames = load("res://source/common/gameplay/combat/vfx/lash_burst.tres") as SpriteFrames
		if burst != null:
			SpriteEffect.spawn(player, burst, {"scale": Vector2(0.7, 0.7), "offset": Vector2(0.0, -8.0), "z_index": 1})
		return
	var visual: ChannelVisual = ChannelVisual.new()
	visual.name = "ChannelVisual"
	visual.duration = float(payload.get("d", 6.0))
	visual.radius = float(payload.get("r", 60.0))
	visual.kind = kind
	player.add_child(visual)
	# The wielded weapon strikes its channel stance (the hammer plants + floats).
	# Recall isn't a weapon channel, so the weapon stays neutral for it.
	if kind != &"recall":
		var weapon: Weapon = player.equipment_component.mounted_nodes.get(&"weapon", null) as Weapon
		if weapon != null:
			weapon.set_channeling_pose(true)


## A nearby player raised their guard (Last Stand) — flash the shield VFX on them
## (every client, so you read allies/enemies popping a defensive too). The buff
## itself is server-authoritative; this is purely the visual.
static func _on_guard_cast(payload: Dictionary) -> void:
	if current == null:
		return
	var player: Player = current.players_by_peer_id.get(int(payload.get("p", 0)), null)
	if player == null:
		return
	# Persistent floor aura for the whole buff (the honest "I'm guarding" tell). The
	# colour is overridable so the same push drives Berserk's RED rage aura too. A
	# one-shot nova (Static Field) sends aura:false — it wants only the flash below.
	if bool(payload.get("aura", true)):
		var aura: GuardAura = GuardAura.new()
		aura.duration = float(payload.get("d", 6.0))
		if payload.has("col"):
			aura.color = payload.get("col")
		player.add_child(aura)
	# Brief shield flash on cast (the dramatic moment; a one-shot, not a bubble).
	var fx_path: String = String(payload.get("fx", ""))
	if fx_path.is_empty():
		return
	var frames: SpriteFrames = ResourceLoader.load(fx_path) as SpriteFrames
	if frames == null:
		return
	var sc: float = float(payload.get("sc", 0.7))
	SpriteEffect.spawn(player, frames, {
		"scale": Vector2(sc, sc),
		"modulate": payload.get("mod", Color.WHITE),
		"offset": Vector2(0.0, -6.0),
		"z_index": 1,
		"saturation": float(payload.get("sat", 1.0)),
		"loop": bool(payload.get("loop", false)),  # a lingering field loops its ring...
		"duration": float(payload.get("dur", 0.0)),  # ...for this long, then frees
	})


## Battle Form: the colossus entrance. The caster FREEZES and grows the whole ROOT (body,
## weapon, bar, name) PROGRESSIVELY over the wind-up, then is a free titan for the rest of
## the duration, then shrinks back. The server grants HP + the big hurtbox at once
## (BattleFormState). The progressive grow IS the counterplay — enemies see it coming.
## The local player's Camera2D is a child of the root, so each grow step we set the camera
## scale to 1/root so the view never zooms. A slowed rune plays under the body, fixed-size
## on the map (not a child) so it doesn't balloon with the grow.
static func _on_battleform(payload: Dictionary) -> void:
	if current == null:
		return
	var player: Player = current.players_by_peer_id.get(int(payload.get("p", 0)), null)
	if player == null:
		return
	var sc: float = float(payload.get("sc", 1.6))
	var rune_build: float = float(payload.get("rb", 1.0))
	var grow_s: float = float(payload.get("g", 1.2))
	var windup: float = rune_build + grow_s
	var cam: Node2D = player.get_node_or_null(^"Camera2D") as Node2D

	# Ground rune the titan rises from — fixed-size on the MAP (so the grow doesn't balloon it),
	# under the body. SEQUENCED: the BUILD frames play over rune_build then HOLD at full while
	# the body grows; the FADE frames play after. Position captured now (caster's frozen).
	var map: Node = player.get_parent()
	var rune_pos: Vector2 = player.global_position + Vector2(0, 6)
	var build_fx: SpriteEffect = null
	if map != null:
		var build: SpriteFrames = load("res://source/common/gameplay/combat/vfx/battle_rune_build.tres") as SpriteFrames
		if build != null:
			# 7 build frames @ 14fps stretched over rune_build, then held.
			build_fx = SpriteEffect.spawn(map, build, {"scale": Vector2(1.3, 1.3), "z_index": -1, "hold": true,
				"speed_scale": 7.0 / (14.0 * maxf(0.1, rune_build))})
			if build_fx != null:
				build_fx.global_position = rune_pos

	# Freeze the local caster for the whole wind-up (others can act on it — the counterplay).
	if player == ClientState.local_player:
		(player as LocalPlayer).freeze_movement(windup)

	# SEQUENCED: hold normal size while the rune builds, THEN grow over grow_s (rune at full),
	# keeping the camera compensated every step (1/root scale).
	var grow: Tween = player.create_tween()
	grow.tween_interval(rune_build)
	grow.tween_method(func(f: float) -> void:
		if is_instance_valid(player):
			player.scale = Vector2(f, f)
			if cam != null and is_instance_valid(cam):
				cam.scale = Vector2(1.0 / f, 1.0 / f),
		1.0, sc, grow_s)

	# Wind-up done → swap the held rune for the one-shot fade.
	await player.get_tree().create_timer(windup).timeout
	if is_instance_valid(build_fx):
		build_fx.queue_free()
	if map != null and is_instance_valid(map):
		var fade: SpriteFrames = load("res://source/common/gameplay/combat/vfx/battle_rune_fade.tres") as SpriteFrames
		if fade != null:
			var fade_fx: SpriteEffect = SpriteEffect.spawn(map, fade, {"scale": Vector2(1.3, 1.3), "z_index": -1})
			if fade_fx != null:
				fade_fx.global_position = rune_pos

	await player.get_tree().create_timer(maxf(0.0, float(payload.get("d", 8.0)) - windup)).timeout
	if is_instance_valid(player):
		player.scale = Vector2.ONE
		if cam != null and is_instance_valid(cam):
			cam.scale = Vector2.ONE


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
		Client.subscribe(&"guard.cast", _on_guard_cast)
		Client.subscribe(&"battleform.start", _on_battleform)
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
