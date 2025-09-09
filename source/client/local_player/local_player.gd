class_name LocalPlayer
extends Player


var speed: float = 75.0
var hand_pivot_speed: float = 17.5

var input_direction: Vector2 = Vector2.ZERO
var last_input_direction: Vector2 = Vector2.ZERO
var action_input: bool = false
var interact_input: bool = false

var state: String = "idle"

var instance_client: InstanceClient
var synchronizer_manager: StateSynchronizerManagerClient

@onready var mouse: Node2D = $MouseComponent


func _ready() -> void:
	Events.local_player_ready.emit(self)
	super()
	fid_position = PathRegistry.id_of(":position")
	fid_flipped = PathRegistry.id_of(":flipped")
	fid_anim = PathRegistry.id_of(":anim")
	fid_pivot = PathRegistry.id_of(":pivot")


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
	if action_input and equipped_weapon_right.can_use_weapon(0):
		instance_client.player_action.rpc_id(1, 0, position.direction_to(mouse.position))
	interact_input = Input.is_action_just_pressed("interact")


func update_animation(delta: float) -> void:
	flipped = (mouse.position.x < global_position.x)
	update_hand_pivot(delta)


func update_hand_pivot(delta: float) -> void:
	#if action_input:
	var hands_rot_pos = hand_pivot.global_position
	var flips: int = -1 if flipped else 1
	var look_at_mouse: float = atan2(
		(mouse.position.y - hands_rot_pos.y), 
		(mouse.position.x - hands_rot_pos.x) * flips
		)
	hand_pivot.rotation = lerp_angle(hand_pivot.rotation, look_at_mouse, delta * hand_pivot_speed)
	#else:
		#hand_pivot.rotation = lerp_angle(hand_pivot.rotation, 0, delta * hand_pivot_speed)
	anim = Animations.RUN if input_direction else Animations.IDLE


var fid_position: int = PathRegistry.id_of(":position")
var fid_flipped: int = PathRegistry.id_of(":flipped")
var fid_anim: int = PathRegistry.id_of(":anim")
var fid_pivot: int = PathRegistry.id_of(":pivot")
func define_sync_state() -> void:
	var pairs: Array[Array] = [
		[fid_position, global_position],
		[fid_flipped, flipped],
		[fid_anim, anim],
		[fid_pivot, snappedf(hand_pivot.rotation, 0.05)],
	]
	syn.mark_many_by_id(pairs, true)
	synchronizer_manager.send_my_delta(
		multiplayer.get_unique_id(), syn.collect_dirty_pairs()
	)


func _set_character_class(new_class: String):
	character_resource = ResourceLoader.load(
		"res://source/common/gameplay/characters/classes/character_collection/" +
		new_class + ".tres"
	)
	animated_sprite.sprite_frames = character_resource.character_sprite
	character_class = new_class
