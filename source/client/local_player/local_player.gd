class_name LocalPlayer
extends Player


signal sync_state_defined(sync_state: Dictionary)

var speed: float = 75.0
var hand_pivot_speed: float = 17.5

var input_direction: Vector2 = Vector2.ZERO
var last_input_direction: Vector2 = Vector2.ZERO
var action_input: bool = false
var interact_input: bool = false

var state: String = "idle"

@onready var mouse: Node2D = $MouseComponent


func _ready() -> void:
	super()


func _physics_process(delta: float) -> void:
	check_inputs()
	move()
	update_animation(delta)
	define_sync_state()


func move() -> void:
	velocity = input_direction * speed
	move_and_slide()


func check_inputs() -> void:
	input_direction = Input.get_vector("left", "right", "up", "down")
	match input_direction:
		Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN:
			last_input_direction = input_direction
	action_input = Input.is_action_pressed("action")
	interact_input = Input.is_action_just_pressed("interact")


func update_animation(delta: float) -> void:
	flipped = (mouse.position.x < global_position.x)
	update_hand_pivot(delta)


func update_hand_pivot(delta: float) -> void:
	if action_input:
		var hands_rot_pos = hand_pivot.global_position
		var flips := -1 if flipped else 1
		var look_at_mouse := atan2(
			(mouse.position.y - hands_rot_pos.y), 
			(mouse.position.x - hands_rot_pos.x) * flips
			)
		hand_pivot.rotation = lerp_angle(hand_pivot.rotation, look_at_mouse, delta * hand_pivot_speed)
	else:
		hand_pivot.rotation = lerp_angle(hand_pivot.rotation, 0, delta * hand_pivot_speed)
		anim = Animations.RUN if input_direction else Animations.IDLE


func define_sync_state() -> void:
	sync_state = {
		"T": Time.get_unix_time_from_system(),
		"position": get_global_position(),
		"flipped": flipped,
		"anim": anim,
		"pivot": snappedf(hand_pivot.rotation, 0.05)
	}


func _set_character_class(new_class: String):
	character_resource = ResourceLoader.load(
		"res://source/common/resources/custom/character/character_collection/" +
		new_class + ".tres"
	)
	animated_sprite.sprite_frames = character_resource.character_sprite
	ClientEvents.health_changed.emit(
		character_resource.base_health + 
		character_resource.health_per_level * 0,# Should be player_resource.level
		true
	)
	character_class = new_class


func _set_sync_state(new_state: Dictionary) -> void:
	var update_state: Dictionary

	for key: String in new_state:
		if not sync_state.has(key) or sync_state[key] != new_state[key]:
			update_state[key] = new_state[key]

	sync_state = new_state
	if update_state.size() > 1:
		sync_state_defined.emit(update_state)
