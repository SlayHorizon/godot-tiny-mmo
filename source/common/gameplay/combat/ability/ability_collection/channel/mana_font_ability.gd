class_name ManaFontAbility
extends ChannelAbility
## A rooted MANA channel — the healing aura's arcane twin: every tick, restore
## [member mana_restore_per_tick] mana to the caster AND to nearby allied players
## within [member radius]. The post-fight group refuel circle ("stand here to
## recover your mana"). You're planted while it runs; moving cancels it.
##
## Server-authoritative; the blue aura ring renders from the channel push
## (ChannelVisual kind &"mana_font").

## Mana restored per tick to each valid target (caster + nearby allies).
@export var mana_restore_per_tick: float = 4.0


## Lead with the mana-per-second, then the channel lines from ChannelAbility.
func extra_stat_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("+%s mana/s" % fmt_num(mana_restore_per_tick / tick_interval_s))
	lines.append_array(super())
	return lines


func channel_tick(caster: Character) -> void:
	if not GameMode.is_world_server() or not is_instance_valid(caster):
		return
	# Same ally rule as the healing aura: the channeler always; then living allied
	# Players in radius (CombatHit.are_allied — spar teammates / guildmates).
	_restore(caster)
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
			_restore(target)


func _restore(target: Character) -> void:
	var current: float = target.stats_component.get_stat(Stat.MANA)
	var maximum: float = target.stats_component.get_stat(Stat.MANA_MAX)
	if current >= maximum:
		return
	target.stats_component.set_stat(Stat.MANA, minf(current + mana_restore_per_tick, maximum))
