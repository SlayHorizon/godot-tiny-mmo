class_name LocalPlayer
extends Player


var speed: float = 75.0
var hand_pivot_speed: float = 17.5

var input_direction: Vector2 = Vector2.ZERO
var action_input: bool = false

var fid_position: int
var fid_flipped: int
var fid_anim: int
var fid_pivot: int

var synchronizer_manager: StateSynchronizerManagerClient

@onready var mouse: Node2D = $MouseComponent


func _ready() -> void:
	Events.local_player = self
	Events.local_player_ready.emit(self)
	
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
	input_direction = Input.get_vector("left", "right", "up", "down")
	action_input = Input.is_action_pressed("action")
	if action_input and equipment_component.can_use(&"weapon", 0):
		InstanceClient.current.request_data(&"action.perform", Callable(),
		{"d": global_position.direction_to(mouse.position), "i": 0})


func process_animation(delta: float) -> void:
	flipped = (mouse.position.x < global_position.x)
	update_hand_pivot(delta)
	anim = Animations.RUN if input_direction else Animations.IDLE


func update_hand_pivot(delta: float) -> void:
	var hands_rot_pos: Vector2 = hand_pivot.global_position
	var flips: int = -1 if flipped else 1
	var look_at_mouse: float = atan2(
		(mouse.position.y - hands_rot_pos.y),
		(mouse.position.x - hands_rot_pos.x) * flips
	)
	hand_pivot.rotation = lerp_angle(hand_pivot.rotation, look_at_mouse, delta * hand_pivot_speed)


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
	if Events.settings.has("zoom"):
		$Camera2D.zoom = Vector2.ONE * Events.settings["zoom"]
