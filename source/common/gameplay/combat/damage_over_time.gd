class_name DamageOverTime
extends Node
## A server-side damage tick (burn, poison, ...) attached to its VICTIM as a
## child node, so it dies with the victim's node and needs no manager. One
## node per effect kind — re-applying the same kind REFRESHES duration and
## ownership instead of stacking (bolt spam can't pile burns).
##
## Damage goes through Character.take_damage directly: the zone/PvP gates ran
## on the hit that APPLIED the effect (CombatHit.try_damage), and a burn that
## stops at a zone line would feel arbitrary anyway.


var source: Character
var damage_per_tick: float
var damage_type: StringName = CombatHit.DAMAGE_MAGIC
## Effect family (&"burn", &"poison", ...) — the node name carries it for
## refresh lookups, this exposes it for the status HUD.
var kind: StringName
var _remaining_ticks: int


## Whole seconds left, for the status-icon countdown.
func remaining_seconds() -> int:
	return maxi(0, _remaining_ticks)


## Attach (or refresh) a DoT on [param victim]. Server-side only; clients see
## the health drain through the regular stat sync.
static func apply(
	victim: Character,
	from: Character,
	effect_kind: StringName,
	dps: float,
	duration_s: float,
	type: StringName = CombatHit.DAMAGE_MAGIC
) -> void:
	if victim == null or not victim.multiplayer.is_server() or dps <= 0.0:
		return
	var node_name: String = "DoT_%s" % effect_kind
	var existing: DamageOverTime = victim.get_node_or_null(NodePath(node_name)) as DamageOverTime
	if existing != null:
		existing.source = from
		existing.damage_per_tick = dps
		existing._remaining_ticks = maxi(existing._remaining_ticks, ceili(duration_s))
		return
	var dot: DamageOverTime = DamageOverTime.new()
	dot.name = node_name
	dot.kind = effect_kind
	dot.source = from
	dot.damage_per_tick = dps
	dot.damage_type = type
	dot._remaining_ticks = ceili(duration_s)
	victim.add_child(dot)


func _ready() -> void:
	var timer: Timer = Timer.new()
	timer.wait_time = 1.0
	timer.timeout.connect(_tick)
	add_child(timer)
	timer.start()


func _tick() -> void:
	var victim: Character = get_parent() as Character
	if victim == null or victim.is_dead or _remaining_ticks <= 0:
		queue_free()
		return
	_remaining_ticks -= 1
	victim.take_damage(damage_per_tick, source, damage_type)
	if _remaining_ticks <= 0:
		queue_free()
