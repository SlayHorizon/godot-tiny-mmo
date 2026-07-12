class_name HazardZone
extends Area2D
## Server-only lingering damage zone (refactor P4): the puffcap's spore cloud
## today, band-4 poison pools tomorrow. Ticks magic damage to every living
## player inside its radius until it expires, then frees itself. Spawned by
## server logic (DeathBurstBehavior) as a plain sibling of the mob — runtime
## children are invisible to the replication container's sync, and clients see
## a separately replicated rp_ visual instead (HostileNpc.rp_hazard_zone).
##
## The first tick is delayed one interval, so stepping THROUGH a fresh cloud
## is safe and standing in it is the mistake — walking out is the dodge.

var radius: float = 48.0
var duration_s: float = 3.0
var tick_interval_s: float = 0.5
var damage_per_tick: float = 5.0
## Attribution for the damage (the dead mob). May be freed mid-zone
## (a despawned single-life mob) — ticks fall back to sourceless damage.
var source: Character

var _expire_at_ms: int
var _next_tick_ms: int


func _ready() -> void:
	collision_layer = 0
	collision_mask = CombatHit.TARGET_MASK
	var shape: CollisionShape2D = CollisionShape2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
	add_child(shape)
	var now: int = Time.get_ticks_msec()
	_expire_at_ms = now + int(duration_s * 1000.0)
	_next_tick_ms = now + int(tick_interval_s * 1000.0)


func _physics_process(_delta: float) -> void:
	var now: int = Time.get_ticks_msec()
	if now >= _expire_at_ms:
		queue_free()
		return
	if now < _next_tick_ms:
		return
	_next_tick_ms = now + int(tick_interval_s * 1000.0)
	var attribution: Character = source if is_instance_valid(source) else null
	for area: Area2D in get_overlapping_areas():
		if area is not HurtBox:
			continue
		var target: Character = (area as HurtBox).character
		if target is Player and not target.is_dead:
			target.take_damage(damage_per_tick, attribution, CombatHit.DAMAGE_MAGIC)
