class_name Projectile
extends Area2D
## Base for EVERY fired projectile (arrows, wand bolts, heal bolts, and any future one). It owns the
## whole hit pipeline in ONE place: move, detect, and react. Detection is a per-frame SHAPE QUERY
## (the same mechanism melee uses) rather than area/body_entered — enter-events only fire on a
## boundary crossing, so they miss a target the projectile spawns INSIDE (point-blank / packed mobs)
## or blows past in a single frame. The query catches them all, at any speed.
##
## Subclasses customise ONLY the per-hit response by overriding [method _resolve_hit]; they never
## re-implement detection, walls, piercing, or the Arcane-Wall pass-through. See HealBolt.

var speed: float = 200.0
var direction: Vector2 = Vector2.RIGHT

var piercing: bool = false
var pierce_left: int = 0
var source: Node

## Server-authoritative damage on impact, set by the spawning weapon (charge ratio, multishot…).
var damage: float = 5.0
## Mitigation channel: ARMOR for physical (arrows), MR for magic (wand bolts).
var damage_type: StringName = CombatHit.DAMAGE_PHYSICAL

## Optional damage-over-time applied on a DAMAGED hit (Ember Bolt's burn, Venom Shot's poison).
## 0 dps = none. [member dot_kind] picks the status family (drives the debuff icon).
var burn_dps: float = 0.0
var burn_duration_s: float = 0.0
var dot_kind: StringName = &"burn"

## Seconds a projectile flies before despawning if it hits nothing (speed × this ≈ max range).
const LIFETIME: float = 1.2

## Max distance moved between hit checks. A fast projectile (or a frame-time spike under load) moves
## speed×frametime per frame; if that exceeds the hit shape, a point-blank target can fall BETWEEN two
## static overlap checks and get skipped. Sub-stepping the move to ≤ this (half the 16px hit shape)
## makes detection continuous — speed- and framerate-independent. 1 step at normal speed, so ~free.
const MAX_STEP_PX: float = 8.0

## Colliders already handled this flight (instance_id) — so a piercing shot hits each target once
## and a lingering overlap isn't re-resolved every frame.
var _hit_ids: Dictionary[int, bool] = {}


func _ready() -> void:
	# What a hit can land on: hurtboxes (damage) + flags (capture) + world (block). NOT character
	# navigation bodies — attacks hit the body-sized HurtBox area instead. See docs/combat_layers.md.
	collision_mask = CombatHit.TARGET_MASK
	if not multiplayer.is_server():
		var vosn: VisibleOnScreenNotifier2D = VisibleOnScreenNotifier2D.new()
		vosn.screen_exited.connect(queue_free)
		add_child(vosn)
	rotate(direction.angle())
	# Lifetime cap so stray shots don't sail across the map. TODO: a projectile manager beats a timer each.
	var timer: Timer = Timer.new()
	timer.wait_time = LIFETIME
	timer.one_shot = true
	timer.timeout.connect(queue_free)
	add_child(timer)
	timer.start()


func _physics_process(delta: float) -> void:
	# Move in sub-steps no bigger than MAX_STEP_PX, running the shape query after each, so a fast shot
	# (or a frame-time spike under load) can't jump PAST a point-blank target between two checks. The
	# per-frame shape query alone is STATIC — that's what let fast bolts (380) and charged arrows (400)
	# skip close targets while slow taps (200) landed. Runs on both peers: the server applies damage,
	# the client stops its own visual (take_damage is gated). collide_with_areas catches HurtBoxes;
	# bodies catch walls/flags.
	var move: Vector2 = speed * direction * delta
	var steps: int = maxi(1, ceili(move.length() / MAX_STEP_PX))
	var step: Vector2 = move / float(steps)
	for _i: int in steps:
		position += step
		for collider: Node2D in CombatHit.overlapping_bodies(self):
			_handle_collision(collider)
			if not is_instance_valid(self):
				return


## Resolve one collider once: skip self / already-handled, drain an Arcane Wall, otherwise run the
## subclass response and react to it (stop on a wall, pierce, or pass a non-target).
func _handle_collision(node: Node2D) -> void:
	if node == source:
		return
	var id: int = node.get_instance_id()
	if _hit_ids.has(id):
		return
	_hit_ids[id] = true # each collider handled once per flight

	# Arcane Wall: a damage-pool shield. Eats up to its remaining HP; the OVERFLOW punches through
	# (a big nuke is reduced, not fully negated). Deterministic across peers (same synced damage).
	if node is Barrier:
		var overflow: float = (node as Barrier).absorb(damage)
		if overflow <= 0.0:
			queue_free() # fully absorbed
			return
		damage = overflow # reduced — keep flying to whatever's behind the wall
		return

	match _resolve_hit(node):
		CombatHit.Result.IGNORED:
			return # friendly / safe-zone / non-target — keep flying
		CombatHit.Result.BLOCKED:
			queue_free() # wall / door — stop here
		CombatHit.Result.DAMAGED:
			# Ride a burn on top if this projectile carries one (server applies; clients see the sync).
			if burn_dps > 0.0 and multiplayer.is_server():
				var victim: Node2D = node
				if victim is HurtBox:
					victim = (victim as HurtBox).character
				if victim is Character:
					DamageOverTime.apply(victim as Character, source as Character, dot_kind, burn_dps, burn_duration_s, damage_type)
			if not piercing or pierce_left <= 0:
				queue_free()
			pierce_left -= 1


## What this projectile DOES to [param node], returning how the base reacts: IGNORED = pass through,
## DAMAGED = consumed (or pierce), BLOCKED = stop. Default = deal damage via CombatHit (which
## resolves a HurtBox to its Character, applies the target rules, and deals the hit). Override for a
## different effect — see HealBolt. Server-authoritative: damage is gated inside take_damage.
func _resolve_hit(node: Node2D) -> CombatHit.Result:
	return CombatHit.try_damage(source as Character, node, damage, damage_type)
