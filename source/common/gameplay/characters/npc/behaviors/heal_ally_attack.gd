class_name HealAllyAttack
extends MobAttack
## The support mob's tool (refactor P3 — the band-3 sorcerer): pick the
## most-wounded living ALLY in range and fire the REAL heal-bolt ability at it —
## the same wand_heal.tres players use, priced by the same formula (heal = AP ×
## ap_ratio), so a sorcerer's healing is tuned through its archetype's
## attack_damage (the chassis mirrors AD into AP). No wounded ally → doesn't
## fire, and the swing falls through to the next attack in the array: a
## sorcerer heals when needed, bolts otherwise.
##
## The bolt is a real projectile: a DIFFERENT wounded ally crossing the line
## can consume it (fine — the recharge retries), a full-HP ally never does
## (HealBolt flies past those), and players kill it by killing the caster.
## Keep sorcerer arenas open-field by map design; nothing here paths around
## walls.

## The heal ability (assign ability_collection/bolt_shoot/wand_heal.tres).
## Must be registry-indexed — the client replay resolves it by slug.
@export var ability: AbilityResource


func _init() -> void:
	# The pick below is hardwired to the most-wounded ally; keep the inherited
	# inspector knob truthful instead of showing the enemy-targeting default.
	target_policy = TargetPolicy.LOWEST_HP_ALLY
## How far the caster scans for wounded allies.
@export var heal_range: float = 140.0


func _fire(npc) -> bool:
	if ability == null:
		return false
	var ally: HostileNpc = _most_wounded_ally(npc)
	if ally == null:
		return false
	var direction: Vector2 = npc.global_position.direction_to(ally.global_position)
	ability.auto_use(npc, direction)
	npc.replicate_visual(&"rp_cast_ability", [_ability_slug(), direction])
	return true


## Most-wounded living ally within heal_range, scanned from the mob's own
## replication container (where every mob in the instance lives — no extra
## tracking structure). Full-HP allies don't count as targets.
func _most_wounded_ally(npc) -> HostileNpc:
	if npc.container == null:
		return null
	var best: HostileNpc = null
	var best_hp: float = INF
	for child: Node in npc.container.get_children():
		if child is not HostileNpc or child == npc:
			continue
		var ally: HostileNpc = child as HostileNpc
		if ally.is_dead or not CombatHit.are_allied_npcs(npc, ally):
			continue
		if npc.global_position.distance_to(ally.global_position) > heal_range:
			continue
		var hp: float = ally.stats_component.get_stat(Stat.HEALTH)
		if hp >= ally.stats_component.get_stat(Stat.HEALTH_MAX):
			continue # topped off — nothing to heal
		if hp < best_hp:
			best_hp = hp
			best = ally
	return best


func _ability_slug() -> StringName:
	return StringName(String(ability.get_meta(&"slug",
			ability.resource_path.get_file().get_basename())))
