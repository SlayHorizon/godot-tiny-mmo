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
var _teleport_lock_until_ms: int = 0

func _on_sparring_match_state(payload: Dictionary) -> void:
	var pos: Variant = payload.get("position", null)
	if pos is Vector2 and pos != Vector2.ZERO:
		global_position = pos
		_teleport_lock_until_ms = Time.get_ticks_msec() + 500
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
		_teleport_lock_until_ms = Time.get_ticks_msec() + 500


func _physics_process(delta: float) -> void:
	process_input()
	process_movement()
	process_animation(delta)
	process_synchronization()


func process_movement() -> void:
	if _dead or Time.get_ticks_msec() < _teleport_lock_until_ms:
		velocity = Vector2.ZERO
		return
	# Read the server-synced MOVE_SPEED stat so AGILITY (and speed gear) actually
	# move you faster. Fall back to `speed` until the first stat sync lands so the
	# player isn't frozen on spawn.
	var move_speed: float = stats_component.get_stat(Stat.MOVE_SPEED)
	velocity = input_direction * (move_speed if move_speed > 0.0 else speed)
	move_and_slide()


func process_input() -> void:
	if _dead or _has_gui_focus() or Time.get_ticks_msec() < _teleport_lock_until_ms:
		input_direction = Vector2.ZERO
		action_input = false
		return

	input_direction = controller.get_move_direction()
	look_direction = controller.get_look_direction()
	action_input = controller.is_attack_pressed()
	
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
