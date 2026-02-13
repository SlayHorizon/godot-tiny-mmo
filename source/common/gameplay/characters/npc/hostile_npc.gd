class_name HostileNpc
extends Character


enum EnemyState {
	RETURNING,
	IDLE,
	CHASE,
	ATTACK,
	DEAD
}

## Start chasing the player once he steps in the area.
@export var chase_on_area: bool = false
## The distance between the player and NPC to start attacking.
@export var distance_to_attack: int = 20
## The max distance from spawn. If NPC pass the limit, trigger the returning.
@export var max_distance_from_spawn: int = 100
@export var move_speed: int = 20

@export var detection_area: Area2D

var container: ReplicatedPropsContainer
var enemy_state: EnemyState = EnemyState.IDLE

var possible_targets: Array[Player]
var targeted_player: Player
var spawn_position: Vector2

var _prop_id: int
var _position_fid: int
var _anim_fid: int
var _state_fid: int


func _ready() -> void:
	assert(get_parent() is ReplicatedPropsContainer, "HostileNPC must be a child of ReplicatedPropContainer.")
	if not multiplayer.is_server():
		set_physics_process(false)
		return
	
	assert(detection_area != null, "HostileNPC must have a Area2D.")
	detection_area.body_entered.connect(_on_body_entered)
	detection_area.body_exited.connect(_on_body_exited)

	spawn_position = global_position
	container = get_parent()

	_prop_id = container.child_id_of_node(self)
	_position_fid = PathRegistry.ensure_id(^":position")
	_anim_fid = PathRegistry.ensure_id(^":anim")
	_state_fid = PathRegistry.register_field(":enemy_state", Wire.Type.VARIANT)


func _physics_process(_delta: float) -> void:
	if not multiplayer.is_server(): return
	
	match enemy_state:
		EnemyState.RETURNING:
			_process_return()
		EnemyState.IDLE:
			pass
		EnemyState.CHASE:
			_process_chase()
		EnemyState.ATTACK:
			_process_attack()
		EnemyState.DEAD:
			_process_death()

	_find_targets()
	_process_animations()
	_process_synchronization()


func _on_body_entered(body: Node) -> void:
	if body is not Player: return

	if possible_targets.has(body):
		possible_targets.set(possible_targets.find(body, 0), body)
	else:
		possible_targets.append(body)
	
	if chase_on_area and not targeted_player:
		targeted_player = body
		enemy_state = EnemyState.CHASE


func _on_body_exited(body: Node) -> void:
	if body is not Player: return
	if body == targeted_player: return

	possible_targets.erase(body)	


func _find_targets() -> void:
	if targeted_player: return
	if enemy_state == EnemyState.RETURNING: return
	if possible_targets.is_empty(): return

	targeted_player = possible_targets[0]
	enemy_state = EnemyState.CHASE


func _process_animations() -> void:
	match enemy_state:
		EnemyState.RETURNING:
			if anim != Character.Animations.RUN:
				anim = Character.Animations.RUN
		EnemyState.IDLE:
			if anim != Character.Animations.IDLE:
				anim = Character.Animations.IDLE
		EnemyState.CHASE:
			if anim != Character.Animations.RUN:
				anim = Character.Animations.RUN


func _process_synchronization() -> void:
	container.mark_child_prop(_prop_id, _position_fid, position, true)
	container.mark_child_prop(_prop_id, _anim_fid, anim, true) 
	container.mark_child_prop(_prop_id, _state_fid, enemy_state, true)


func _process_return() -> void:
	var direction: Vector2 = position.direction_to(spawn_position)
	velocity = direction * move_speed
	move_and_slide()

	# implement HP regenetation with combat logic.

	var distance_from_spawn: float = position.distance_to(spawn_position)
	if distance_from_spawn < 10: # minimum distance from spawn.
		enemy_state = EnemyState.IDLE


func _process_chase() -> void:
	if not targeted_player: return
	
	var direction: Vector2 = position.direction_to(targeted_player.global_position)
	velocity = direction * move_speed
	move_and_slide()

	var distance_from_spawn: float = position.distance_to(spawn_position)
	if distance_from_spawn > max_distance_from_spawn:
		stop_chase()
		return

	var distance_from_player: float = position.distance_to(targeted_player.global_position)
	if distance_from_player < distance_to_attack:
		enemy_state = EnemyState.ATTACK
		return


func _process_attack() -> void:
	if not targeted_player: return

	# to implement with combat.

	var distance_from_player: float = position.distance_to(targeted_player.global_position)
	if distance_from_player > distance_to_attack:
		enemy_state = EnemyState.CHASE


func _process_death() -> void:
	# to implement with combat.
	pass

## If npc is chasing a player, stops chasing and start returning to spawn position.
func stop_chase() -> void:
	if enemy_state != EnemyState.CHASE: return
	enemy_state = EnemyState.RETURNING
	possible_targets.erase(targeted_player)
	targeted_player = null
