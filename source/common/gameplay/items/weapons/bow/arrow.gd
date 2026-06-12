class_name Projectile
extends Area2D

var speed: float = 200.0
var direction: Vector2 = Vector2.RIGHT

var piercing: bool = false
var pierce_left: int = 0
var source: Node

## Server-authoritative damage this arrow deals on impact. Set by the
## spawning weapon (bow charge ratio, multishot fraction, etc.). Defaults
## to a small fallback so a legacy spawn that forgot to set it doesn't
## nuke the target.
var damage: float = 5.0
## Mitigation channel: ARMOR for physical (arrows), MR for magic (wand bolts).
var damage_type: StringName = CombatHit.DAMAGE_PHYSICAL

## Optional damage-over-time applied on a DAMAGED hit (Ember Bolt's burn).
## 0 = none. Set by the spawning ability alongside damage.
var burn_dps: float = 0.0
var burn_duration_s: float = 0.0

## Seconds an arrow flies before despawning if it hits nothing. Short so stray
## shots don't sail across the whole map (speed × this ≈ max range).
const LIFETIME: float = 1.2

func _ready() -> void:
	# Detect the same layers as melee (combatants + flags + walls) so arrows stop
	# on geometry. On BOTH peers: the server applies damage, the client stops its
	# own visual (take_damage is server-gated, so the client deals none).
	collision_mask = CombatHit.TARGET_MASK
	body_entered.connect(_on_body_entered)
	if not multiplayer.is_server():
		var vosn := VisibleOnScreenNotifier2D.new()
		vosn.screen_exited.connect(queue_free)
		add_child(vosn)
	rotate(direction.angle())

	# One timer by bullet is bad practice.
	# TODO MOVE IT TO A MANAGER
	var timer: Timer = Timer.new()
	timer.wait_time = LIFETIME
	timer.one_shot = true
	timer.timeout.connect(queue_free)
	add_child(timer)
	timer.start() # was missing — arrows never timed out, only despawned on hit/off-screen


func _physics_process(delta: float) -> void:
	position += speed * direction * delta


func _on_body_entered(body: Node2D) -> void:
	if body == source:
		return
	# Shared target rules (flags, PvP zones, sparring, guild friendly-fire) in one
	# place — see CombatHit. The result tells the projectile how to react.
	match CombatHit.try_damage(source as Character, body, damage, damage_type):
		CombatHit.Result.IGNORED:
			return # friendly / safe-zone / non-target — keep flying
		CombatHit.Result.BLOCKED:
			queue_free() # hit a wall / door — stop here
		CombatHit.Result.DAMAGED:
			# The gated hit landed — ride a burn on top if this projectile
			# carries one (server applies; clients see the health drain sync).
			if burn_dps > 0.0 and multiplayer.is_server() and body is Character:
				DamageOverTime.apply(body as Character, source as Character, &"burn", burn_dps, burn_duration_s, damage_type)
			if not piercing or pierce_left <= 0:
				queue_free()
			pierce_left -= 1
