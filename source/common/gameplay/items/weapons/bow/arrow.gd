class_name Projectile
extends Area2D

var speed: float = 200.0
var direction: Vector2 = Vector2.RIGHT

var piercing: bool = false
var pierce_left: int = 0
# OLD
var source: Node
var attack: Attack
# NEW
var effect: EffectSpec

func _ready() -> void:
	# Quick and dirty for tests - Need proper system
	if multiplayer.is_server():
		body_entered.connect(_on_body_entered)
	else:
		var vosn := VisibleOnScreenNotifier2D.new()
		vosn.screen_exited.connect(queue_free)
		add_child(vosn)
	rotate(direction.angle())

	# One timer by bullet is bad practice.
	# TODO MOVE IT TO A MANAGER
	var timer: Timer = Timer.new()
	timer.wait_time = 3.0
	timer.one_shot = true
	timer.timeout.connect(queue_free)
	add_child(timer)


func _physics_process(delta: float) -> void:
	position += speed * direction * delta


func _on_body_entered(body: Node2D) -> void:
	if body == source:
		return

	# Flags are damageable by any player projectile — bypass character-vs-character
	# rules (PvP zones, NPC friendly-fire) since a flag isn't a combatant.
	if body is TerritoryFlag:
		if source is not Player:
			return
		var flag_damage: float = 10.0
		if source is Character:
			flag_damage = maxf(flag_damage, source.stats_component.get_stat(Stat.AD))
		body.take_damage(flag_damage, source if source is Character else null)
		if not piercing or pierce_left <= 0:
			queue_free()
		pierce_left -= 1
		return

	if body is not Character:
		return

	# No NPC-vs-NPC friendly fire (until proper teams exist).
	if source is not Player and body is not Player:
		return

	# Player-vs-player only lands in PvP zones; NPC->player (PvE) damage always lands.
	# Sparring is the explicit exception: if both fighters are in a live match
	# (countdown over), zone rules don't matter — the arena hosts the fight.
	if body is Player and source is Player and not body.is_pvp():
		if not (SparringService.is_pvp_live_for(body as Player) and SparringService.is_pvp_live_for(source as Player)):
			return

	# Damage scales with the shooter's Attack (falls back to a small base), and is
	# mitigated by the target's armor inside take_damage.
	var damage: float = 10.0
	if source is Character:
		damage = maxf(damage, source.stats_component.get_stat(Stat.AD))
	body.take_damage(damage, source if source is Character else null)

	if not piercing or pierce_left <= 0:
		queue_free()
	pierce_left -= 1
