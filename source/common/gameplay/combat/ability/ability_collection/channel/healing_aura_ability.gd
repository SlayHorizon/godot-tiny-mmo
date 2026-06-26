class_name HealingAuraAbility
extends ChannelAbility
## A rooted healing channel: every tick, restore [member heal_per_tick] HP to the
## caster AND to nearby players within [member radius]. Slow but steady — the
## tank-cleric's sustain. You're planted while it runs (moving cancels it), which
## is the counterplay. Tiers grow the heal + radius as an upgrade chain in the
## hammer Resolve branch.
##
## Server-authoritative; the green aura renders from the channel push and each
## heal pops a green number via the existing combat.hit heal feedback.

## HP restored per tick to each valid target (caster + nearby players).
@export var heal_per_tick: float = 3.0


func channel_tick(caster: Character) -> void:
	if not GameMode.is_world_server() or not is_instance_valid(caster):
		return
	# Always heal the channeler; then every living ALLY within radius. "Ally" is
	# the shared CombatHit.are_allied rule (spar teammates in a match, guildmates
	# otherwise) — the same definition the wand heal + damage gate use, so it's
	# correct in cross-guild spar teams and never tops up an enemy. Mobs aren't
	# Player nodes, so the type filter excludes them too.
	_heal(caster)
	if caster is not Player:
		return
	var container: Node = caster.get_parent()
	if container == null:
		return
	for node: Node in container.get_children():
		if node == caster or node is not Player:
			continue
		var target: Character = node as Character
		if target.is_dead:
			continue
		if not CombatHit.are_allied(caster as Player, node as Player):
			continue
		if caster.global_position.distance_to(target.global_position) <= radius:
			_heal(target)


## Restore heal_per_tick, clamped to max HP, and pop a green heal number (reusing
## the combat.hit heal path) for the HP actually gained.
func _heal(target: Character) -> void:
	var current: float = target.stats_component.get_stat(Stat.HEALTH)
	var maximum: float = target.stats_component.get_stat(Stat.HEALTH_MAX)
	if current >= maximum:
		return
	var healed: float = minf(current + heal_per_tick, maximum)
	target.stats_component.set_stat(Stat.HEALTH, healed)
	var gained: int = int(round(healed - current))
	if gained <= 0 or WorldServer.curr == null:
		return
	var container: Node = target.get_parent()
	if container == null or container.get_parent() == null:
		return
	WorldServer.curr.propagate_rpc(
		WorldServer.curr.data_push.bind(&"combat.hit", {
			"amount": gained,
			"position": target.global_position,
			"heal": true,
		}),
		container.get_parent().name
	)
