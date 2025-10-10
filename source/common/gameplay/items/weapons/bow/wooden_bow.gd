extends Weapon


enum State {
	READY,
	CHARGING,
	CHARGED,
}

@export var cooldown: float = 0.8
@export var charge_time_s: float = 0.4
@export var min_damage: float = 10.0
@export var max_damage: float = 30.0
@export var min_speed: float = 400.0
@export var max_speed: float = 900.0

var state: State = State.READY
var charge_start: float = -1.0
var cooldown_until: float = 0.0


func _ready() -> void:
	super._ready()
	var now: float = Time.get_ticks_msec() / 1000.0
	cooldown_until = now + cooldown
	# Don't bother loading animation stuff on server
	if multiplayer.is_server():
		return
	if character.animation_player.has_animation_library(&"weapon"):
		return
	character.animation_player.add_animation_library(
		&"weapon",
		animation_libraries[&"weapon"]
	)


func try_perform_action(action_index: int, direction: Vector2) -> bool:
	if not can_use_weapon(action_index):
		return false
	
	perform_action(action_index, direction)

	return true


func can_use_weapon(action_index: int) -> bool:
	var now: float = Time.get_ticks_msec() / 1000.0
	match action_index:
		0:
			return state == State.READY and now >= cooldown_until
		1:
			return state == State.CHARGING or state == State.CHARGED
		_:
			return false


func perform_action(action_index: int, direction: Vector2) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	match action_index:
		0:
			state = State.CHARGING
			charge_start = now
			if not multiplayer.is_server():
				character.weapon_state_machine.travel(&"weapon_charge")
		1:
			state = State.READY
			charge_start = -1.0
			cooldown_until = now + cooldown
			shoot_arrow(character, direction)
			if not multiplayer.is_server():
				character.weapon_state_machine.travel(&"weapon_idle")


func process_input(local_player: LocalPlayer) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	# Check cooldown locally here too to avoid spamming server with requests.
	if Input.is_action_just_pressed(&"action") and can_use_weapon(0):
		state = State.CHARGING
		InstanceClient.current.request_data(
			&"action.perform", Callable(),
			{"d": local_player.global_position.direction_to(local_player.mouse.position), "i": 0}
		)
	elif Input.is_action_just_released(&"action") and can_use_weapon(1):
		state = State.READY
		InstanceClient.current.request_data(
			&"action.perform", Callable(),
			{"d": local_player.global_position.direction_to(local_player.mouse.position), "i": 1}
		)


func shoot_arrow(entity: Entity, direction: Vector2) -> void:
	var arrow: Projectile = preload("res://source/common/gameplay/items/weapons/bow/arrow.tscn").instantiate()
	arrow.top_level = true
	arrow.direction = direction
	arrow.global_position = character.right_hand_spot.global_position
	#arrow.global_position = entity.global_position
	
	arrow.source = entity
	arrow.effect = EffectSpec.damage(
		max_damage, ["Damage.Physical", "Projectile", "BasicAttack"], {"pen_tier":1}
	)
	
	entity.add_child(arrow)
