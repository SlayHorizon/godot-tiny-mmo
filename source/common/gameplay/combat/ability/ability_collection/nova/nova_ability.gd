class_name NovaAbility
extends AbilityResource
## A one-shot AoE burst CENTERED on the caster — damages (AP-scaled, MAGIC) every enemy
## in radius and optionally slows Players hit. The book's self-centered novas (Static
## Field; later the Frost Nova / Blood Feast base). Reuses the centered MeleeArc for hit
## detection + the guard.cast push (aura:false) for the ring VFX on every client.
##
## Server-authoritative damage; the ring renders from the push, so the action.perform
## echo can't double it. Mobs take the damage; the slow lands on Players only (it rides
## BuffService, which is player-only) — fine for v1, mob-slow is a later extension.


## Damage as a fraction of the caster's AP.
@export var ap_ratio: float = 0.8
## Burst radius (hit + the ring VFX size).
@export var radius: float = 80.0
## On-hit slow handed to the arc (flat move-speed cut + duration). 0 = no slow.
@export var slow_amount: float = 0.0
@export var slow_duration_s: float = 0.0
## Blood Feast drain: each enemy hit heals + restores mana to the caster (mana only on a
## real hit). 0 = a plain damage nova (Static Field).
@export var heal_per_hit: float = 0.0
@export var mana_per_hit: float = 0.0
## > 0 turns this into a LINGERING field that re-strikes every [member tick_interval_s]
## for this many seconds (Static Field), riding the caster. 0 = a single instant nova.
@export var duration_s: float = 0.0
@export var tick_interval_s: float = 0.5
## The centered hitbox scene (a MeleeArc with a CircleShape2D).
@export var arc_scene: PackedScene = preload("res://source/common/gameplay/combat/melee_arc_centered.tscn")
## Ring VFX shown on the caster (sent by path in the cast push so clients load it).
@export var vfx: SpriteFrames
@export var vfx_color: Color = Color(1, 1, 1, 1)
## The VFX sheet's frame WIDTH in px — the scale math sizes the visual so the art spans
## ~the hit diameter. 128 for the ring/spiral packs; 256 for wide sheets (frost spikes).
@export var vfx_frame_px: float = 128.0


const CAST_RUNE: SpriteFrames = preload("res://source/common/gameplay/combat/vfx/battle_rune_build.tres")


## A cast time (cast_time_s on the .tres) telegraphs the nova with a ground rune at the
## caster's feet — enemies see it coming — then the burst/field lands. 0 = instant (the old
## behavior, e.g. Static Field). The caster is NOT rooted during the cast, just committed.
func use_ability(user: Entity, _direction: Vector2) -> void:
	if user is not Character:
		return
	if GameMode.is_client() and cast_time_s > 0.0:
		SpriteEffect.spawn(user, CAST_RUNE, {
			"scale": Vector2(radius / 90.0, radius / 90.0),
			"offset": Vector2(0.0, 6.0),  # a rune on the ground at the caster's feet
			"z_index": -1,
			"modulate": vfx_color,
			"speed_scale": 7.0 / (16.0 * cast_time_s),  # 7 build frames stretched over the cast
		})
	if not GameMode.is_world_server():
		return
	if cast_time_s > 0.0:
		(user as Character).get_tree().create_timer(cast_time_s).timeout.connect(_spawn_nova.bind(user as Character))
	else:
		_spawn_nova(user as Character)


## Spawns the actual burst/field — split out so the cast time can defer it.
func _spawn_nova(caster: Character) -> void:
	if not is_instance_valid(caster) or caster.is_dead or caster.get_parent() == null or arc_scene == null:
		return
	var dmg: float = caster.stats_component.get_stat(Stat.AP) * ap_ratio
	if duration_s > 0.0:
		# Lingering field: a SpellField re-strikes every tick for the duration, riding us.
		var field: SpellField = SpellField.new()
		field.caster = caster
		field.arc_scene = arc_scene
		field.radius = radius
		field.damage = dmg
		field.damage_type = CombatHit.DAMAGE_MAGIC
		field.slow_amount = slow_amount
		field.slow_duration_s = slow_duration_s
		field.heal_per_hit = heal_per_hit
		field.mana_per_hit = mana_per_hit
		field.tick_interval = tick_interval_s
		field.duration = duration_s
		caster.add_child(field)
	else:
		# Single instant nova.
		var arc: MeleeArc = arc_scene.instantiate()
		arc.source = caster
		var shape_node: CollisionShape2D = arc.get_node_or_null(^"CollisionShape2D") as CollisionShape2D
		if shape_node != null and shape_node.shape is CircleShape2D:
			var circle: CircleShape2D = shape_node.shape.duplicate()
			circle.radius = radius
			shape_node.shape = circle
		arc.damage = dmg
		arc.damage_type = CombatHit.DAMAGE_MAGIC
		arc.slow_amount = slow_amount
		arc.slow_duration_s = slow_duration_s
		arc.heal_per_hit = heal_per_hit
		arc.mana_per_hit = mana_per_hit
		caster.get_parent().add_child(arc)
		arc.global_position = caster.global_position
	_broadcast_ring(caster)


## Shows the ring on every client via the reused guard.cast push (no persistent aura).
func _broadcast_ring(caster: Character) -> void:
	if vfx == null or WorldServer.curr == null or caster is not Player:
		return
	var player: Player = caster as Player
	if player.player_resource == null:
		return
	var map: Node = caster.get_parent()
	if map == null or map.get_parent() == null:
		return
	WorldServer.curr.propagate_rpc(
		WorldServer.curr.data_push.bind(&"guard.cast", {
			"p": int(player.player_resource.current_peer_id),
			"fx": vfx.resource_path,
			"sc": (radius * 2.0) / maxf(1.0, vfx_frame_px),  # art spans ~the hit diameter
			"mod": vfx_color,
			"aura": false,
			"loop": duration_s > 0.0,  # a field loops its ring for the duration
			"dur": duration_s,
		}),
		map.get_parent().name
	)


func extra_stat_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("%d%% AP" % int(round(ap_ratio * 100.0)))
	if slow_amount > 0.0:
		lines.append("-%s move speed for %ss" % [fmt_num(slow_amount), fmt_num(slow_duration_s)])
	lines.append("%dpx radius" % int(radius))
	return lines
