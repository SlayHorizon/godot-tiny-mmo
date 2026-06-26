class_name LocalPlayer
extends Player

## Toast tint for the SAFE <-> PvP zone-crossing notice — red warns of danger,
## green signals protection. Defined locally because ZonePatch2D (which owns the
## canonical zone colors) is an @tool node that's stripped from client exports.
const PVP_TOAST_COLOR: Color = Color(1.0, 0.5, 0.45)
const SAFE_TOAST_COLOR: Color = Color(0.55, 0.95, 0.6)

## Godot Camera2D's default (effectively unbounded) limit magnitude — restored on maps
## that define no camera_limits so a previous map's bounds don't linger.
const CAMERA_LIMIT_MIN: int = -10000000
const CAMERA_LIMIT_MAX: int = 10000000


## Fallback move speed until the synced MOVE_SPEED stat arrives. Actual movement
## reads the stat (see process_movement) so AGILITY / gear speed bonuses apply.
var speed: float = 90.0
var hand_pivot_speed: float = 17.5

var input_direction: Vector2 = Vector2.ZERO
var look_direction: Vector2 = Vector2.ZERO
var action_input: bool = false

## While dead, input/movement are locked so the player can't act or drift; the respawn
## teleport is applied locally (position is client-authoritative).
var _dead: bool = false
var _respawn_position: Vector2

## Last-seen PvP state, so the zone-crossing toast fires only on the SAFE<->PVP
## edge. zone_flags is server-authoritative (synced via correction); we just
## watch the value flip rather than adding another network message.
var _was_pvp: bool = false

var fid_position: int
var fid_flipped: int
var fid_anim: int
var fid_pivot: int

var synchronizer_manager: StateSynchronizerManagerClient

@onready var camera_2d: Camera2D = $Camera2D
@onready var controller: InputComponent = $InputComponent


func _ready() -> void:
	ClientState.local_player = self
	ClientState.local_player_ready.emit(self)
	
	super._ready()

	# Seed the zone-crossing baseline so we don't toast for the spawn state.
	_was_pvp = is_pvp()

	fid_position = PathRegistry.id_of(":position")
	fid_flipped = PathRegistry.id_of(":flipped")
	fid_anim = PathRegistry.id_of(":anim")
	fid_pivot = PathRegistry.id_of(":pivot")
	
	_apply_settings()
	ClientState.settings.setting_changed.connect(_on_settings_changed)
	# Clamp the camera to each map's authored bounds (no black borders past the edge). The
	# local player persists across maps (InstanceClient reuses it), so re-apply on every
	# instance change — plus once now for the map we spawned into.
	Client.instance_manager.instance_changed.connect(_on_instance_changed_camera_limits)
	if InstanceClient.current != null:
		_apply_camera_limits(InstanceClient.current.instance_map)
	Client.subscribe(&"player.died", _on_player_died)
	# Sparring: explicit teleport push at match start (to spawn) and end (back
	# to the duel master). State-sync deltas alone can't move the LocalPlayer
	# because process_movement overwrites with current input each frame; we
	# need to actually set the position here AND freeze input briefly so the
	# player doesn't run off the spot they were teleported to.
	Client.subscribe(&"sparring.match.state", _on_sparring_match_state)
	# Staff teleports (/goto, /summon) within the same map: same problem as the
	# sparring teleport — we must set position locally + freeze input briefly.
	Client.subscribe(&"player.teleport", _on_teleport)
	# Channeling (healing aura, future recall): when OUR channel starts we root in
	# place; pressing a move key cancels it. Other players' channels only show
	# their aura (handled in InstanceClient) — these handlers ignore them.
	Client.subscribe(&"channel.start", _on_channel_start)
	Client.subscribe(&"channel.end", _on_channel_end)
	# Weapon equip-cast: a short draw where abilities are locked (movement + aim
	# stay free) and a cast bar shows over our head. Server pushes start + done.
	Client.subscribe(&"equip.cast", _on_equip_cast)
	Client.subscribe(&"equip.done", _on_equip_done)
	# Co-op group roster (dungeons): mirror our groupmate peer ids so their health
	# bars tint as allies. Same pattern as the sparring team push.
	Client.subscribe(&"group.roster", _on_group_roster)
	# Dungeon cleared (final room down) — show the recap; the server returns the
	# party to town after a short timer (the recap auto-closes with it).
	Client.subscribe(&"dungeon.cleared", func(payload: Dictionary) -> void:
		ClientState.open_menu_requested.emit(&"dungeon_recap", payload))
	# Dungeon FAILED (hardcore wipe — revive pool spent): same recap menu, "failed" variant.
	Client.subscribe(&"dungeon.failed", func(payload: Dictionary) -> void:
		ClientState.open_menu_requested.emit(&"dungeon_recap", payload))
	# Dungeon entered — a soft welcome toast so the run doesn't start abruptly.
	Client.subscribe(&"dungeon.entered", func(payload: Dictionary) -> void:
		Toaster.toast_group(
			"Entered %s" % str(payload.get("dungeon", "the dungeon")),
			PackedStringArray(["Clear each room — defeat the boss to escape."]),
			4.0))
	# Boss enrage (dungeon phase 2): a red banner + camera shake so the escalation
	# reads — see BossController._announce_enrage.
	Client.subscribe(&"boss.enrage", func(payload: Dictionary) -> void:
		Toaster.toast("%s enrages!" % str(payload.get("name", "The boss")), 3.0, PVP_TOAST_COLOR)
		shake_camera(0.6))


## The local player's own over-head HP bar reads as "self" (green), never
## ally/neutral. (Overrides Player so the local-player check stays out of Player —
## see the cycle note there.)
func _apply_team_bar_color() -> void:
	set_health_bar_fill(BAR_COLOR_SELF)


## Lock control while dead, then teleport ourselves to the spawn point (the server owns
## HP + the dead flag; position is ours to set).
func _on_player_died(data: Dictionary) -> void:
	_dead = true
	_respawn_position = data.get("spawn", global_position)
	await get_tree().create_timer(float(data.get("respawn_in", 3.0))).timeout
	if not is_instance_valid(self):
		return
	global_position = _respawn_position
	_dead = false


## Server-driven teleport for the start/end of a sparring match. Pushes carry
## the new position; we apply it and freeze input briefly so the player
## doesn't immediately walk off the spot.
var _movement_lock_until_ms: int = 0

func _on_sparring_match_state(payload: Dictionary) -> void:
	var pos: Variant = payload.get("position", null)
	if pos is Vector2 and pos != Vector2.ZERO:
		global_position = pos
		_movement_lock_until_ms = Time.get_ticks_msec() + 500
	# Spar-team tinting: remember allies/opponents for the match (cleared on end)
	# and re-tint everyone in the map so health bars flip immediately.
	if bool(payload.get("in_match", false)):
		Character.spar_ally_peers = payload.get("allies", [])
		Character.spar_opponent_peers = payload.get("opponents", [])
	else:
		Character.spar_ally_peers = []
		Character.spar_opponent_peers = []
	var map: Node = get_parent()
	if map != null:
		for child: Node in map.get_children():
			if child.has_method(&"_apply_team_bar_color"):
				child.call(&"_apply_team_bar_color")


## Co-op group roster push — set our groupmate peer ids and re-tint everyone in
## the map so their health bars flip to ally immediately (same as spar teams).
func _on_group_roster(payload: Dictionary) -> void:
	Character.group_peers = payload.get("members", [])
	var map: Node = get_parent()
	if map != null:
		for child: Node in map.get_children():
			if child.has_method(&"_apply_team_bar_color"):
				child.call(&"_apply_team_bar_color")


## Generic server-driven teleport (staff /goto, /summon within the same map).
func _on_teleport(payload: Dictionary) -> void:
	var pos: Variant = payload.get("position", null)
	if pos is Vector2:
		global_position = pos
		_movement_lock_until_ms = Time.get_ticks_msec() + 500


# --- Channeling (healing aura, future recall) ---
## True while WE are mid-channel: rooted, actions suppressed, a move key cancels.
## Deliberately NOT the movement lock — that zeroes input, which would make the
## move-to-cancel impossible to detect.
var _channeling: bool = false
## Safety net so a dropped channel.end can't strand us rooted forever.
var _channel_until_ms: int = 0
## Name of the ability WE'RE channeling (empty = none). The ability bar reads
## this off the local player — the HUD lives outside the instance's multiplayer
## context, so it can't identify "us" via get_unique_id; LocalPlayer can.
var channeling_ability_name: String = ""


func _on_channel_start(payload: Dictionary) -> void:
	if int(payload.get("p", -1)) != multiplayer.get_unique_id():
		return # someone else's channel — InstanceClient draws their aura, we don't root
	_channeling = true
	channeling_ability_name = String(payload.get("an", ""))
	_channel_until_ms = Time.get_ticks_msec() + int(float(payload.get("d", 6.0)) * 1000.0) + 750


func _on_channel_end(payload: Dictionary) -> void:
	if int(payload.get("p", -1)) != multiplayer.get_unique_id():
		return
	_channeling = false
	channeling_ability_name = ""


## Tell the server to stop our channel (it pushes channel.end back, which also
## clears the flag — calling this just unroots us a frame early, locally).
func _cancel_channel() -> void:
	_channeling = false
	channeling_ability_name = ""
	if InstanceClient.current != null:
		Client.request_data(&"channel.cancel", Callable(), {}, InstanceClient.current.name)


## Locally roots movement for [param seconds] — heavy attacks plant you while
## you swing (commitment + readability). Reuses the same movement lock, so it
## also blocks re-attacking for that window; fine because the weapons that use
## it have long cooldowns. Called client-side from the weapon on the wielder.
func freeze_movement(seconds: float) -> void:
	if seconds <= 0.0:
		return
	_movement_lock_until_ms = maxi(_movement_lock_until_ms, Time.get_ticks_msec() + int(seconds * 1000.0))


## True while a real WEAPON (one with a primary attack) is in hand — i.e. combat mode.
## Bare hands, a held potion, or a held material all read as UNARMED. The world click-
## to-inspect gate uses this: you only open a player's profile while holstered, so a
## click in a fight is always a shot, never a profile.
func is_armed() -> bool:
	var weapon: Weapon = equipment_component.mounted_nodes.get(&"weapon", null) as Weapon
	return weapon != null and not weapon.abilities.is_empty() and weapon.abilities[0] != null


# --- Weapon equip-cast (client) ---
## True while drawing a weapon: abilities are locked (process_input + the touch
## ability bar both read this), but movement + aim stay free. Set from equip.cast,
## cleared on equip.done — or a safety timeout if that push is lost.
var _equip_drawing: bool = false
var _equip_draw_until_ms: int = 0
var _equip_draw_token: int = 0
var _equip_bar: ChannelVisual = null


func _on_equip_cast(payload: Dictionary) -> void:
	var ms: int = int(payload.get("ms", 500)) # fallback; the server always sends ms (= Player.WEAPON_DRAW_MS)
	_equip_drawing = true
	_equip_draw_until_ms = Time.get_ticks_msec() + ms
	_equip_draw_token += 1
	var token: int = _equip_draw_token
	_show_equip_bar(float(ms) / 1000.0)
	# Safety: clear if the equip.done push is lost, so we can't get stuck locked.
	await get_tree().create_timer(float(ms) / 1000.0 + 0.6).timeout
	if _equip_draw_token == token:
		_clear_equip_draw()


func _on_equip_done(_payload: Dictionary) -> void:
	_equip_draw_token += 1 # invalidate the pending safety timeout
	_clear_equip_draw()


func _clear_equip_draw() -> void:
	_equip_drawing = false
	if is_instance_valid(_equip_bar):
		_equip_bar.queue_free()
	_equip_bar = null


func _show_equip_bar(duration: float) -> void:
	if is_instance_valid(_equip_bar):
		_equip_bar.queue_free()
	var bar: ChannelVisual = ChannelVisual.new()
	bar.name = "EquipCastVisual"
	bar.kind = &"equip"
	bar.duration = maxf(0.1, duration)
	add_child(bar)
	_equip_bar = bar


## True while mid weapon-draw / drink-cast — abilities are locked (process_input +
## the touch ability bar read this). A weapon draw stays move-free; a drink also
## roots via the movement lock.
func is_equip_drawing() -> bool:
	return _equip_drawing and Time.get_ticks_msec() < _equip_draw_until_ms


# --- Camera shake (combat juice) ---
## Current trauma (0..1). Shake offset is trauma², so it eases out smoothly and
## a big hit doesn't snap to a hard stop. Decays a bit each frame.
var _trauma: float = 0.0
const SHAKE_DECAY: float = 3.5      ## trauma per second bled off
const SHAKE_MAX_OFFSET: float = 9.0 ## pixels at full trauma

## Adds a kick of camera shake (additive, clamped). Call from a weapon's own
## visual when its hit lands — e.g. the hammer slam. [param amount] ~0.3 light,
## ~0.6 heavy.
func shake_camera(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


func _process(delta: float) -> void:
	if _trauma <= 0.0:
		return
	_trauma = maxf(0.0, _trauma - SHAKE_DECAY * delta)
	var shake: float = _trauma * _trauma * SHAKE_MAX_OFFSET
	camera_2d.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * shake


func _physics_process(delta: float) -> void:
	process_input()
	process_movement()
	process_animation(delta)
	process_synchronization()
	_notify_zone_transition()


## Toast when we cross the SAFE <-> PvP boundary. zone_flags is synced from the
## server (StateSynchronizerManagerServer.update_zone_flags_for_entity), so the
## bit simply flips under us as we move — we watch it rather than adding a
## dedicated push. Local-player only: remote players never run this.
func _notify_zone_transition() -> void:
	var now_pvp: bool = is_pvp()
	if now_pvp == _was_pvp:
		return
	_was_pvp = now_pvp
	if now_pvp:
		Toaster.toast("Entered a PvP zone — other players can attack you here.", 3.0, PVP_TOAST_COLOR)
	else:
		Toaster.toast("Back in a safe zone — you're protected from other players.", 3.0, SAFE_TOAST_COLOR)


func process_movement() -> void:
	if _dead or _channeling or ClientState.menu_open or Time.get_ticks_msec() < _movement_lock_until_ms:
		velocity = Vector2.ZERO
		return
	# Read the server-synced MOVE_SPEED stat so AGILITY (and speed gear) actually
	# move you faster. Fall back to `speed` until the first stat sync lands so the
	# player isn't frozen on spawn.
	var move_speed: float = stats_component.get_stat(Stat.MOVE_SPEED)
	velocity = input_direction * (move_speed if move_speed > 0.0 else speed)
	move_and_slide()


func process_input() -> void:
	if _dead or _has_gui_focus() or ClientState.menu_open or Time.get_ticks_msec() < _movement_lock_until_ms:
		input_direction = Vector2.ZERO
		action_input = false
		return

	input_direction = controller.get_move_direction()
	look_direction = controller.get_look_direction()
	action_input = controller.is_attack_pressed()

	# Mid weapon-draw / drink-cast: abilities are locked (the server gates too). A
	# weapon draw stays move-free; a drink roots via the movement lock above.
	if is_equip_drawing():
		action_input = false
		return

	# Recall (B): a universal channel anyone can start — ask the server to begin
	# it. Not while already channeling (re-press is ignored; cancel by moving).
	if Input.is_action_just_pressed(&"player_recall") and not _channeling and InstanceClient.current != null:
		Client.request_data(&"recall.start", Callable(), {}, InstanceClient.current.name)

	# Channeling: rooted (process_movement zeroes velocity). A move key CANCELS
	# the channel and frees us from this frame on; otherwise suppress all actions
	# so an attack can't interrupt it. Safety-clear if the end push was lost.
	if _channeling:
		if Time.get_ticks_msec() > _channel_until_ms:
			_channeling = false
			channeling_ability_name = ""
		elif input_direction != Vector2.ZERO:
			_cancel_channel()
		else:
			action_input = false
			return

	equipment_component.process_input(self)
	if action_input and equipment_component.can_use(&"weapon", 0):
		Client.request_data(&"action.perform", Callable(),
		{"d": look_direction, "i": 0}, InstanceClient.current.name)


func process_animation(delta: float) -> void:
	if _dead:
		# Play (and hold) the death pose instead of input-driven locomotion. Synced to
		# other clients via the :anim field like any other animation.
		if anim != Animations.DEATH:
			anim = Animations.DEATH
		return
	flipped = look_direction.x < 0
	update_hand_pivot(delta)
	anim = Animations.RUN if input_direction else Animations.IDLE


func update_hand_pivot(delta: float) -> void:
	# Channeling plants you in a fixed stance — the weapon holds its angle rather
	# than swivelling to the cursor (a planted hammer that still tracked aim would
	# look wrong). The pose itself is the weapon's set_channeling_pose.
	if _channeling:
		return
	var to_flip: int = -1 if flipped else 1
	var look_angle: float = atan2(look_direction.y, look_direction.x * to_flip)
	hand_pivot.rotation = lerp_angle(hand_pivot.rotation, look_angle, delta * hand_pivot_speed)


func process_synchronization() -> void:
	var pairs: Array[Array] = [
		[fid_position, global_position],
		[fid_flipped, flipped],
		[fid_anim, anim],
		[fid_pivot, snappedf(hand_pivot.rotation, 0.05)],
	]
	state_synchronizer.mark_many_by_id(pairs, true)
	var collected_pairs: Array = state_synchronizer.collect_dirty_pairs()
	if not collected_pairs.is_empty():
		synchronizer_manager.send_my_delta(multiplayer.get_unique_id(), collected_pairs)


func set_camera_zoom(zoom: Vector2) -> void:
	camera_2d.zoom = zoom


func _on_instance_changed_camera_limits(instance: InstanceClient) -> void:
	_apply_camera_limits(instance.instance_map if instance != null else null)


## Clamp the camera to [param map]'s per-edge limits. Each edge defaults to ±CAMERA_LIMIT
## (unbounded), so a map that sets none leaves the camera free — and re-applying on every map
## change naturally clears a previous map's clamps. Called on spawn and on each map change.
func _apply_camera_limits(map: Map) -> void:
	if map == null:
		camera_2d.limit_left = CAMERA_LIMIT_MIN
		camera_2d.limit_top = CAMERA_LIMIT_MIN
		camera_2d.limit_right = CAMERA_LIMIT_MAX
		camera_2d.limit_bottom = CAMERA_LIMIT_MAX
		return
	camera_2d.limit_left = map.camera_limit_left
	camera_2d.limit_top = map.camera_limit_top
	camera_2d.limit_right = map.camera_limit_right
	camera_2d.limit_bottom = map.camera_limit_bottom


## Chat composing gate: while a chat field is focused, kill ALL player input (move, aim,
## attack) so typing on mobile doesn't drive the sticks or fire the weapon, and WASD on
## desktop types instead of moving. Releasing player_shoot clears any stick-latched attack
## so it doesn't keep firing once input is re-enabled. (Complements _has_gui_focus, which
## already gates the polling path — this also stops InputComponent from pressing the attack
## action in the first place.)
func set_input_active(active: bool) -> void:
	controller.enabled = active
	if not active:
		Input.action_release(&"player_shoot")


func _apply_settings() -> void:
	var settings: Dictionary = ClientState.settings.data.get(&"general", {})
	for property_name: StringName in settings:
		_on_settings_changed(&"general", property_name, settings[property_name]) 


func _on_settings_changed(section: StringName, property: StringName, value: Variant) -> void:
	match [section, property]:
		[&"general", &"camera_zoom"]:
			set_camera_zoom(clamp(value, 1.0, 4.0) * Vector2.ONE)


func _has_gui_focus() -> bool:
	var focus: Control = get_viewport().gui_get_focus_owner()
	return focus is LineEdit or focus is TextEdit
