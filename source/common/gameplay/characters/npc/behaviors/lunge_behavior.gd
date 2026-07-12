class_name LungeBehavior
extends MobBehavior
## Telegraphed gap-closer, extracted verbatim from HostileNpc (refactor P1,
## docs/hostile_npc_refactor.md). When the target sits in the pounce window
## (between ~2x melee range and lunge_range), the mob winds up — a red
## corridor marks the LOCKED landing spot — then dashes straight to it,
## damaging players the dash runs over (once each). Fully dodgeable by
## stepping OUT of the corridor during the windup; punishes standing still.

@export var lunge_range: float = 0.0
@export var lunge_radius: float = 24.0
@export var lunge_windup_s: float = 0.55
@export var lunge_speed_multiplier: float = 5.0
@export var lunge_cooldown: float = 5.0


func try_start(npc, distance_to_target: float, now: int) -> bool:
	if lunge_range <= 0.0:
		return false
	var scratch: Dictionary = runtime_state(npc)
	if now < int(scratch.get("ready_at_ms", 0)):
		return false
	# The pounce window: too far to melee, close enough to pounce.
	var lunge_min: float = maxf(npc.distance_to_attack * 2.0, lunge_range * 0.4)
	if distance_to_target < lunge_min or distance_to_target > lunge_range:
		return false
	_begin(npc, scratch)
	return true


func process_state(npc) -> void:
	match npc.enemy_state:
		HostileNpc.EnemyState.LUNGE_WINDUP:
			_process_windup(npc)
		HostileNpc.EnemyState.LUNGING:
			_process_dash(npc)


## Lock the pounce at the target's CURRENT position (not homing — that's the
## dodge), show the corridor on every client, and start the windup.
## Charges THROUGH the target's spot, not TO it: the landing point overshoots
## behind the player (relative to us), so backing straight away stays inside
## the corridor — the only real dodge is stepping OUT of it sideways. Also
## keeps the landing point out of the player's collider.
func _begin(npc, scratch: Dictionary) -> void:
	var direction: Vector2 = npc.global_position.direction_to(npc.targeted_player.global_position)
	scratch["direction"] = direction
	scratch["target_position"] = npc.targeted_player.global_position + direction * (lunge_radius * 2.0)
	scratch["phase_until_ms"] = Time.get_ticks_msec() + int(lunge_windup_s * 1000.0)
	scratch["hit"] = {}
	npc.enemy_state = HostileNpc.EnemyState.LUNGE_WINDUP
	npc.velocity = Vector2.ZERO
	# Corridor telegraph (mob → landing spot) so players see WHO is charging
	# and which strip of ground to vacate. Lives through windup + travel time.
	npc.replicate_visual(&"rp_lunge_telegraph", [
		scratch["target_position"], lunge_radius, lunge_windup_s + 0.45
	])
	# Client dash playback, scheduled NOW alongside the telegraph: the whole
	# dash is already determined (mob rooted through the windup, landing
	# locked), so the client's dash starts exactly when its telegraph expires
	# instead of an op-arrival later (see HostileNpc.rp_dash).
	var speed: float = maxf(1.0, float(npc.move_speed) * lunge_speed_multiplier)
	var duration_ms: int = int(npc.global_position.distance_to(scratch["target_position"]) / speed * 1000.0)
	npc.replicate_visual(&"rp_dash", [
		npc.global_position, scratch["target_position"], duration_ms, int(lunge_windup_s * 1000.0)
	])


func _process_windup(npc) -> void:
	var scratch: Dictionary = runtime_state(npc)
	if Time.get_ticks_msec() >= int(scratch.get("phase_until_ms", 0)):
		npc.enemy_state = HostileNpc.EnemyState.LUNGING
		# Safety deadline: a wall-stuck pounce lands where it got stuck instead
		# of dashing forever.
		scratch["deadline_ms"] = Time.get_ticks_msec() + 1200


## Straight-line dash with the heading locked at windup. Termination is by
## PROJECTION onto that heading — once we reach or pass the landing plane
## (even after sliding around a collider) the dash is over. No re-aiming →
## no jitter, ever.
func _process_dash(npc) -> void:
	var scratch: Dictionary = runtime_state(npc)
	var direction: Vector2 = scratch.get("direction", Vector2.RIGHT)
	var target_position: Vector2 = scratch.get("target_position", npc.global_position)
	var remaining: float = (target_position - npc.global_position).dot(direction)
	if remaining <= 8.0 or Time.get_ticks_msec() >= int(scratch.get("deadline_ms", 0)):
		_land(npc, scratch)
		return
	npc.velocity = direction * npc.move_speed * lunge_speed_multiplier
	npc.move_and_slide()
	# The DASH is the attack: anyone the mob runs over inside the corridor
	# takes the hit (once per lunge). Per-tick distance check is sweep-safe —
	# at ~5px of travel per physics tick the radius can't tunnel past a player.
	var hit: Dictionary = scratch["hit"]
	var damage: float = npc.stats_component.get_stat(Stat.AD)
	for candidate: Player in npc._strike_candidates():
		if hit.has(candidate.get_instance_id()):
			continue
		if npc._is_target_valid(candidate) and npc._is_hostile_to(candidate) \
				and npc.global_position.distance_to(candidate.global_position) <= lunge_radius:
			hit[candidate.get_instance_id()] = true
			candidate.take_damage(damage, npc)


## Touchdown: start the cooldown and hand control back to the normal brain.
## (Damage already happened in-flight — the dash itself is the hitbox.)
func _land(npc, scratch: Dictionary) -> void:
	scratch["ready_at_ms"] = Time.get_ticks_msec() + int(lunge_cooldown * 1000.0)
	# The windup+dash took ~a second — the target legitimately moved meanwhile.
	# Reset the escape tracker so that movement isn't misread as a teleport.
	npc._tracked_target = null
	if npc._is_target_valid(npc.targeted_player):
		npc.enemy_state = HostileNpc.EnemyState.CHASE
	else:
		npc._abandon_target()
