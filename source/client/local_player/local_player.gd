class_name LocalPlayer
extends Player


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
	
	fid_position = PathRegistry.id_of(":position")
	fid_flipped = PathRegistry.id_of(":flipped")
	fid_anim = PathRegistry.id_of(":anim")
	fid_pivot = PathRegistry.id_of(":pivot")
	
	_apply_settings()
	ClientState.settings.setting_changed.connect(_on_settings_changed)
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
	# Generic server-driven root (consuming a potion, future cast times): no
	# teleport, just freeze movement + actions for the pushed duration.
	Client.subscribe(&"player.freeze", _on_freeze)
	# Channeling (healing aura, future recall): when OUR channel starts we root in
	# place; pressing a move key cancels it. Other players' channels only show
	# their aura (handled in InstanceClient) — these handlers ignore them.
	Client.subscribe(&"channel.start", _on_channel_start)
	Client.subscribe(&"channel.end", _on_channel_end)


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


## Generic server-driven teleport (staff /goto, /summon within the same map).
func _on_teleport(payload: Dictionary) -> void:
	var pos: Variant = payload.get("position", null)
	if pos is Vector2:
		global_position = pos
		_movement_lock_until_ms = Time.get_ticks_msec() + 500


## Server-driven root with no teleport (potion sip, future cast times). The
## movement-lock gate freezes both movement and actions for the duration.
func _on_freeze(payload: Dictionary) -> void:
	var ms: int = int(payload.get("ms", 0))
	if ms > 0:
		_movement_lock_until_ms = maxi(_movement_lock_until_ms, Time.get_ticks_msec() + ms)


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


func process_movement() -> void:
	if _dead or _channeling or Time.get_ticks_msec() < _movement_lock_until_ms:
		velocity = Vector2.ZERO
		return
	# Read the server-synced MOVE_SPEED stat so AGILITY (and speed gear) actually
	# move you faster. Fall back to `speed` until the first stat sync lands so the
	# player isn't frozen on spawn.
	var move_speed: float = stats_component.get_stat(Stat.MOVE_SPEED)
	velocity = input_direction * (move_speed if move_speed > 0.0 else speed)
	move_and_slide()


func process_input() -> void:
	if _dead or _has_gui_focus() or Time.get_ticks_msec() < _movement_lock_until_ms:
		input_direction = Vector2.ZERO
		action_input = false
		return

	input_direction = controller.get_move_direction()
	look_direction = controller.get_look_direction()
	action_input = controller.is_attack_pressed()

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
