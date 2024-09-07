class_name LocalPlayer
extends Player

signal sync_state_defined(sync_state: Dictionary)

var speed: float = 75.0

var input_direction: Vector2 = Vector2.ZERO
var last_input_direction: Vector2 = Vector2.ZERO
var action_input: bool = false
var interact_input: bool = false

var state: String = "idle"

@onready var mouse: Node2D = $MouseComponent

func _ready() -> void:
	pass

func _physics_process(_delta: float) -> void:
	check_inputs()
	move()
	update_animation()
	define_sync_state()


func move() -> void:
	velocity = input_direction * speed
	move_and_slide()

func check_inputs() -> void:
	input_direction = Input.get_vector("left", "right", "up", "down")
	match input_direction:
		Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN:
			last_input_direction = input_direction
	action_input = Input.is_action_just_pressed("action")
	interact_input = Input.is_action_just_pressed("interact")

func update_animation() -> void:
	flipped = (mouse.position.x < global_position.x)
	hand_pivot.look_at(mouse.position)
	anim = Animations.RUN if input_direction else Animations.IDLE

func define_sync_state() -> void:
	sync_state = {
		"T": Time.get_unix_time_from_system(),
		"position": get_global_position(),
		"flipped": flipped,
		"anim": anim,
		"pivot": snappedf(hand_pivot.rotation, 0.05)
	}

func _set_sync_state(new_state: Dictionary) -> void:
	var update_state: Dictionary

	for key: String in new_state:
		if not sync_state.has(key) or sync_state[key] != new_state[key]:
			update_state[key] = new_state[key]

	sync_state = new_state
	if update_state.size() > 1:
		sync_state_defined.emit(update_state)
