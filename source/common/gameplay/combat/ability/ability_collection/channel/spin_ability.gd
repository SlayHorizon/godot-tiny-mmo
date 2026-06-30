class_name SpinAbility
extends ChannelAbility
## A whirling melee channel (Whirlwind): every tick, damage all ENEMIES within
## [member radius] for a slice of the wielder's AD. The damage is SPREAD over the
## channel rather than an instant nuke — that's the balance lever, and why it's a
## channel. Mobile by default (see ChannelAbility.mobile), so you walk slowly
## while you spin. Reuses the channel machinery + CombatHit's allegiance / PvP /
## friendly-NPC / mob rules, so allies and shopkeepers are skipped for free. The
## sword's signature, Domination branch.

## Damage per tick to each enemy in range = caster AD × this ratio.
@export var damage_ratio: float = 0.3
## The hitbox spawned each tick — a CENTERED arc sized to [member radius]. Reuses
## the melee-arc physics query, so it hits MOBS (a tree-iteration loop missed them:
## HostileNpcs aren't reliable siblings of the player) AND respects CombatHit's
## allegiance/PvP rules.
@export var arc_scene: PackedScene = preload("res://source/common/gameplay/combat/melee_arc_centered.tscn")


func channel_tick(caster: Character) -> void:
	if not GameMode.is_world_server() or not is_instance_valid(caster):
		return
	if caster.get_parent() == null or arc_scene == null:
		return
	var arc: MeleeArc = arc_scene.instantiate()
	arc.source = caster
	# Resize the (duplicated) hitbox to the spin radius — never the shared sub-resource.
	var shape_node: CollisionShape2D = arc.get_node_or_null(^"CollisionShape2D") as CollisionShape2D
	if shape_node != null and shape_node.shape is CircleShape2D:
		var circle: CircleShape2D = shape_node.shape.duplicate()
		circle.radius = radius
		shape_node.shape = circle
	arc.damage = caster.stats_component.get_stat(Stat.AD) * damage_ratio
	caster.get_parent().add_child(arc)
	arc.global_position = caster.global_position


## Whirlwind stats for the mastery detail panel (damage/sec, spin length, mana/sec).
func extra_stat_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	var per_sec: float = damage_ratio / maxf(0.1, tick_interval_s)
	lines.append("%d%% AD/s" % int(round(per_sec * 100.0)))
	lines.append("%ss spin" % fmt_num(channel_duration_s))
	if mana_per_tick > 0.0:
		lines.append("%s mana/s" % fmt_num(mana_per_tick / maxf(0.1, tick_interval_s)))
	return lines
