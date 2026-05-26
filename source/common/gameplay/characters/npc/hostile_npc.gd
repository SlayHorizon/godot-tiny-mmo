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

@export_group("Combat")
## Identifier used by quest KILL objectives (e.g. &"slime"). Enemies sharing a type
## count toward the same objective.
@export var enemy_type: StringName
@export var max_health: float = 50.0
@export var attack_damage: float = 8.0
## Seconds between auto-attacks while in range.
@export var attack_cooldown: float = 1.5
@export var armor: float = 0.0
## Optional weapon. If set, the enemy equips it and fires its ability at the target
## (reusing the same projectiles players use, so they're dodgeable). Set distance_to_attack
## to the desired firing range. If null, the enemy is a melee AoE attacker.
@export var weapon: WeaponItem
@export var xp_reward: int = 25
## Seconds before a killed enemy respawns at its spawn point.
@export var respawn_delay: float = 5.0
@export var loot: Array[LootDrop]
@export_group("")

var container: ReplicatedPropsContainer
var enemy_state: EnemyState = EnemyState.IDLE

var possible_targets: Array[Player]
var targeted_player: Player
var spawn_position: Vector2

var _prop_id: int
var _position_fid: int
var _anim_fid: int
var _state_fid: int
var _health_fid: int
var _health_max_fid: int
## When (Time.get_ticks_msec) a dead enemy should respawn.
var _respawn_at_ms: int
## When the next auto-attack is allowed.
var _next_attack_ms: int


func _ready() -> void:
	# Character._ready wires the client-side health bar (stat_changed -> ProgressBar);
	# without this the NPC's bar is never initialised or connected. On the server it
	# returns immediately.
	super._ready()
	# Equip the weapon on both server (to fire/deal damage) and client (visual + to
	# replay the shot). Done before the stat init below so the explicit NPC stats win.
	_equip_weapon()
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
	_health_fid = PathRegistry.ensure_id("StatsComponent:stats:health")
	_health_max_fid = PathRegistry.ensure_id("StatsComponent:stats:health_max")

	# Server-authoritative combat stats.
	stats_component.set_stat(Stat.HEALTH_MAX, max_health)
	stats_component.set_stat(Stat.HEALTH, max_health)
	stats_component.set_stat(Stat.AD, attack_damage)
	stats_component.set_stat(Stat.ARMOR, armor)


func _physics_process(_delta: float) -> void:
	if not multiplayer.is_server():
		return

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
	if enemy_state == EnemyState.RETURNING or enemy_state == EnemyState.DEAD: return

	# First living player still in range (skips dead/freed entries). Re-acquires
	# players who were already inside the area after a respawn.
	for candidate: Player in possible_targets:
		if is_instance_valid(candidate) and not candidate.is_dead:
			targeted_player = candidate
			enemy_state = EnemyState.CHASE
			return


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
		EnemyState.ATTACK:
			if anim != Character.Animations.IDLE:
				anim = Character.Animations.IDLE


func _process_synchronization() -> void:
	container.mark_child_prop(_prop_id, _position_fid, position, true)
	container.mark_child_prop(_prop_id, _anim_fid, anim, true)
	container.mark_child_prop(_prop_id, _state_fid, enemy_state, true)
	container.mark_child_prop(_prop_id, _health_fid, stats_component.get_stat(Stat.HEALTH), true)
	container.mark_child_prop(_prop_id, _health_max_fid, stats_component.get_stat(Stat.HEALTH_MAX), true)


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
	if targeted_player.is_dead:
		_abandon_target()
		return

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
	if not targeted_player or targeted_player.is_dead:
		_abandon_target()
		return

	# Stand and face the target while attacking.
	velocity = Vector2.ZERO

	var distance_from_player: float = position.distance_to(targeted_player.global_position)
	if distance_from_player > distance_to_attack:
		enemy_state = EnemyState.CHASE
		return

	# Auto-attack on cooldown.
	var now: int = Time.get_ticks_msec()
	if now >= _next_attack_ms:
		_next_attack_ms = now + int(attack_cooldown * 1000.0)
		if weapon != null:
			_perform_ranged_attack()
		else:
			_perform_melee_attack()


## A swing: telegraph it on clients (red circle) and damage every living player within
## melee range (a small AoE), each mitigated by their armor in take_damage.
func _perform_melee_attack() -> void:
	container.queue_op(_prop_id, "rp_attack", [float(distance_to_attack)])
	var damage: float = stats_component.get_stat(Stat.AD)
	for candidate: Player in possible_targets:
		if is_instance_valid(candidate) and not candidate.is_dead \
				and position.distance_to(candidate.global_position) <= distance_to_attack:
			candidate.take_damage(damage, self)


## Client-visual: flash the melee-range circle. Called via the container's rp_ op.
func rp_attack(radius: float) -> void:
	if multiplayer.is_server():
		return
	var telegraph: AttackTelegraph = AttackTelegraph.new()
	telegraph.radius = radius
	add_child(telegraph)


## Fires the equipped weapon's ability at the target. The server spawns the real
## (damaging) projectile; clients replay the shot via rp_shoot for the visual.
func _perform_ranged_attack() -> void:
	var mounted: Weapon = equipment_component.mounted_nodes.get(&"weapon")
	if mounted == null:
		return
	var direction: Vector2 = position.direction_to(targeted_player.global_position)
	mounted.auto_attack(direction)
	container.queue_op(_prop_id, "rp_shoot", [direction])


## Client-visual: replay the weapon shot so the projectile flies on every client.
func rp_shoot(direction: Vector2) -> void:
	if multiplayer.is_server():
		return
	var mounted: Weapon = equipment_component.mounted_nodes.get(&"weapon")
	if mounted:
		mounted.auto_attack(direction)


## Equips the configured weapon (server + client) by setting the slot, which mounts it.
func _equip_weapon() -> void:
	if weapon == null or weapon.slot == null:
		return
	equipment_component.slots.set(weapon.slot.key, int(weapon.get_meta(&"id", 0)))


## Called by Character.take_damage when health hits zero (server-only).
func die(killer: Character) -> void:
	enemy_state = EnemyState.DEAD
	anim = Character.Animations.DEATH
	velocity = Vector2.ZERO
	targeted_player = null
	# Keep possible_targets so players still standing in the area are re-acquired on
	# respawn (body_entered won't re-fire for someone who never left).
	_respawn_at_ms = Time.get_ticks_msec() + int(respawn_delay * 1000.0)
	if killer is Player:
		_reward_killer(killer)


## Drops the current target and heads home (used when the target dies or is lost).
func _abandon_target() -> void:
	targeted_player = null
	enemy_state = EnemyState.RETURNING


func _process_death() -> void:
	if Time.get_ticks_msec() < _respawn_at_ms:
		return
	# Respawn at the original spot, full health, idle.
	global_position = spawn_position
	stats_component.set_stat(Stat.HEALTH, stats_component.get_stat(Stat.HEALTH_MAX))
	is_dead = false
	enemy_state = EnemyState.IDLE


## Grants xp + loot to the killing player and pushes feedback to their client.
func _reward_killer(killer: Player) -> void:
	var resource: PlayerResource = killer.player_resource
	if resource == null:
		return

	var progress: Dictionary = resource.add_experience(xp_reward)
	var loot_gained: Array = _roll_loot()
	for entry: Dictionary in loot_gained:
		Inventory.add_item(resource.inventory, int(entry["id"]), int(entry["amount"]))

	var peer_id: int = int(resource.current_peer_id)
	if peer_id > 0:
		WorldServer.curr.data_push.rpc_id(peer_id, &"combat.reward", {
			"xp": xp_reward,
			"level": int(progress.get("level", 1)),
			"levels_gained": int(progress.get("levels_gained", 0)),
			"points_gained": int(progress.get("points_gained", 0)),
			"experience": resource.experience,
			"xp_to_next": resource.level_xp_to_next(),
			"loot": loot_gained,
		})

	# Quest KILL progress for this enemy type.
	var quest_updates: Array = QuestService.on_kill(resource, enemy_type)
	if peer_id > 0 and not quest_updates.is_empty():
		WorldServer.curr.data_push.rpc_id(peer_id, &"quest.update", {"messages": quest_updates})


## Rolls each loot entry; returns [{ "id", "amount", "name" }, ...].
func _roll_loot() -> Array:
	var out: Array = []
	for drop: LootDrop in loot:
		if drop == null or drop.item == null:
			continue
		if randf() <= drop.chance:
			var amount: int = randi_range(drop.min_amount, drop.max_amount)
			if amount > 0:
				out.append({
					"id": int(drop.item.get_meta(&"id", 0)),
					"amount": amount,
					"name": str(drop.item.item_name),
				})
	return out


## If npc is chasing a player, stops chasing and start returning to spawn position.
func stop_chase() -> void:
	if enemy_state != EnemyState.CHASE: return
	enemy_state = EnemyState.RETURNING
	possible_targets.erase(targeted_player)
	targeted_player = null
