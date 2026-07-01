class_name LightningLashAbility
extends ChannelAbility
## A close-range LIGHTNING LASH: a sustained beam you AIM and SWEEP. While channeling you
## move slowly (a mobile channel keeps your aim live) and each tick a beam in your aim
## direction zaps every enemy in the line. The directional counterpart to the self-novas
## (Static Field is retired in its favour). Domination, book.
##
## The beam direction is the LIVE world aim, recovered server-side from the synced hand
## pivot (un-flipping the x) — so the beam follows the cursor as you turn. Each tick spawns
## a rectangle MeleeArc rotated to that aim (AP-scaled, magic).


## Damage per tick to each enemy in the beam = caster AP × this.
@export var ap_ratio: float = 0.35
## Beam reach (kept short — this is a melee-range lash) and width.
@export var beam_length: float = 120.0
@export var beam_width: float = 34.0
## Drain beam (Life Siphon): each enemy the beam hits also heals the caster and restores
## mana. 0 = a plain damage beam (Lightning Lash). Rides MeleeArc's existing drain hooks.
@export var heal_per_hit: float = 0.0
@export var mana_per_hit: float = 0.0
@export var arc_scene: PackedScene = preload("res://source/common/gameplay/combat/melee_arc.tscn")

const CAST_VFX: SpriteFrames = preload("res://source/common/gameplay/combat/vfx/lash_cast.tres")


## A CAST TIME (cast_time_s, set on the .tres) telegraphs the lash: a sky-strike lands on
## the caster — every client sees it coming (like Battle Form's rune) — and when it lands,
## the beam channel begins. The caster is NOT frozen during the cast (unlike Battle Form);
## it's pure warning + commitment, not a root.
func use_ability(user: Entity, direction: Vector2) -> void:
	if user is not Character:
		return
	# Telegraph on every client (this runs on each peer via the action echo).
	if GameMode.is_client() and cast_time_s > 0.0:
		SpriteEffect.spawn(user, CAST_VFX, {
			"scale": Vector2(0.55, 0.55),
			"offset": Vector2(0.0, -100.0),  # the bolt strikes DOWN onto the caster from above
			"z_index": 1,
			"speed_scale": 5.0 / (16.0 * cast_time_s),  # 5 frames @ 16fps stretched over the cast
		})
	if not GameMode.is_world_server():
		return
	# Server: start the beam channel after the cast time (or now if none).
	if cast_time_s > 0.0:
		(user as Character).get_tree().create_timer(cast_time_s).timeout.connect(_start_channel.bind(user as Character))
	else:
		_start_channel(user as Character)


## Mirrors ChannelAbility.use_ability's channel spawn — split out so the cast time can defer it.
func _start_channel(caster: Character) -> void:
	if not is_instance_valid(caster) or caster.is_dead:
		return
	var existing: ChannelInstance = caster.get_node_or_null(^"ChannelInstance") as ChannelInstance
	if existing != null:
		existing.cancel()
	var channel: ChannelInstance = ChannelInstance.new()
	channel.name = "ChannelInstance"
	channel.ability = self
	channel.caster = caster
	caster.add_child(channel)


func channel_tick(caster: Character) -> void:
	if not GameMode.is_world_server() or not is_instance_valid(caster):
		return
	if caster.get_parent() == null or arc_scene == null:
		return
	# Live world aim from the synced hand pivot — the pivot is flip-adjusted for the weapon
	# visual, so un-flip the x to get the real direction.
	var aim: Vector2 = Vector2.from_angle(caster.pivot)
	if caster.flipped:
		aim.x = -aim.x
	var arc: MeleeArc = arc_scene.instantiate()
	arc.source = caster
	var shape_node: CollisionShape2D = arc.get_node_or_null(^"CollisionShape2D") as CollisionShape2D
	if shape_node != null:
		var rect: RectangleShape2D = RectangleShape2D.new()
		rect.size = Vector2(beam_length, beam_width)
		shape_node.shape = rect
		shape_node.position = Vector2(beam_length / 2.0, 0.0)  # extend forward along local +x
	arc.damage = caster.stats_component.get_stat(Stat.AP) * ap_ratio
	arc.damage_type = CombatHit.DAMAGE_MAGIC
	arc.heal_per_hit = heal_per_hit
	arc.mana_per_hit = mana_per_hit
	caster.get_parent().add_child(arc)
	arc.global_position = caster.global_position
	arc.rotation = aim.angle()


func extra_stat_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("%d%% AP per tick" % int(round(ap_ratio * 100.0)))
	lines.append("%dpx beam" % int(beam_length))
	if heal_per_hit > 0.0:
		lines.append("+%s health per hit" % fmt_num(heal_per_hit))
	if mana_per_hit > 0.0:
		lines.append("+%s mana per hit" % fmt_num(mana_per_hit))
	lines.append_array(super())
	return lines
