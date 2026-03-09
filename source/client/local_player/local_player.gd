class_name LocalPlayer
extends Player


var speed: float = 75.0
var hand_pivot_speed: float = 17.5

var input_direction: Vector2 = Vector2.ZERO
var look_direction: Vector2 = Vector2.ZERO # Preparation for multi input support.
var action_input: bool = false

var fid_position: int
var fid_flipped: int
var fid_anim: int
var fid_pivot: int

var synchronizer_manager: StateSynchronizerManagerClient

@onready var camera_2d: Camera2D = $Camera2D
@onready var input: InputComponent = $InputComponent


func _ready() -> void:
	ClientState.local_player = self
	ClientState.local_player_ready.emit(self)
	
	super._ready()
	
	fid_position = PathRegistry.id_of(":position")
	fid_flipped = PathRegistry.id_of(":flipped")
	fid_anim = PathRegistry.id_of(":anim")
	fid_pivot = PathRegistry.id_of(":pivot")
	
	apply_settings()


func _physics_process(delta: float) -> void:
	process_input()
	process_movement()
	process_animation(delta)
	process_synchronization()


func process_movement() -> void:
	velocity = input_direction * speed
	move_and_slide()


func process_input() -> void:
	var gui_focus: Control = get_viewport().gui_get_focus_owner()
	if gui_focus is LineEdit or gui_focus is TextEdit:
		input_direction = Vector2.ZERO
		action_input = false
		return

	input_direction = input.get_move_direction()

	var look_dir: Vector2 = input.get_look_direction()
	if look_dir != Vector2.ZERO:
		look_direction = look_dir


func process_animation(delta: float) -> void:
	flipped = look_direction.x < 0
	update_hand_pivot(delta)
	anim = Animations.RUN if input_direction else Animations.IDLE


func update_hand_pivot(delta: float) -> void:
	var hands_rot_pos: Vector2 = hand_pivot.global_position
	var look_angle = PI - look_direction.angle() if flipped else look_direction.angle()
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


func apply_settings() -> void:
	set_camera_zoom(ClientState.settings.get_key(&"zoom", 2) * Vector2.ONE)
	ClientState.settings.data_changed.connect(_on_settings_changed)


func _on_settings_changed(property: StringName, value: Variant) -> void:
	match property:
		&"camera_zoom":
			set_camera_zoom(clampi(value, 1, 4) * Vector2.ONE)


func set_camera_zoom(zoom: Vector2) -> void:
	camera_2d.zoom = zoom
