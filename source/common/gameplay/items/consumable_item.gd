class_name ConsumableItem
extends Item


## Flat health restored on use. 0 = this consumable doesn't heal.
## Prototype-simple effect; can later move to a data-driven GameplayEffect list.
@export var heal_amount: int
## Flat mana restored on use. 0 = none.
@export var mana_amount: int
## Optional timed buff (via BuffService): the stat to raise (&"mana_regen",
## &"move_speed", ...). Empty = no buff.
@export var buff_stat: StringName = &""
@export var buff_amount: float = 0.0
@export var buff_duration_s: float = 0.0
@export var shared_cooldown_ms: int = 1500
@export var cooldown_category: StringName = &"potion"
## Server roots the drinker in place for this long on use, so you can't run
## and chug at the same time (a sip animation slots in here later). 0 = no
## freeze.
@export var use_freeze_ms: int = 900
## initial charges per single copy if 1 can use the potion one time, if 2 can use the potion 2 times for example.
@export var default_charges: int = 1


func stat_lines() -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	if heal_amount > 0:
		lines.append({"text": "Restores %d health" % heal_amount, "kind": &"heal"})
	if mana_amount > 0:
		lines.append({"text": "Restores %d mana" % mana_amount, "kind": &"mana"})
	if buff_stat != &"" and not is_zero_approx(buff_amount) and buff_duration_s > 0.0:
		var number: String = ("%+d" % int(buff_amount)) if is_equal_approx(buff_amount, roundf(buff_amount)) else ("%+.1f" % buff_amount)
		var duration: String = ("%dm" % int(buff_duration_s / 60.0)) if buff_duration_s >= 60.0 else ("%ds" % int(buff_duration_s))
		lines.append({"text": "%s %s for %s" % [number, Stat.display_name(buff_stat), duration], "stat": StringName(buff_stat)})
	if default_charges > 1:
		lines.append({"text": "%d charges" % default_charges, "kind": &"charges"})
	return lines


func can_use(character: Character) -> bool:
	if character == null:
		return false
	if heal_amount > 0 and character.stats_component.get_stat(Stat.HEALTH) < character.stats_component.get_stat(Stat.HEALTH_MAX):
		return true
	if mana_amount > 0 and character.stats_component.get_stat(Stat.MANA) < character.stats_component.get_stat(Stat.MANA_MAX):
		return true
	# Buff potions always drinkable — re-drinking refreshes the duration.
	if buff_stat != &"" and buff_amount != 0.0 and buff_duration_s > 0.0:
		return true
	return false


## Applies the consumable's effect. Returns true if something actually happened
## (so the caller knows whether to spend a charge / remove it from the bag).
func on_use(character: Character) -> void:
	var stats_component: StatsComponent = character.stats_component
	if heal_amount > 0:
		var healed: float = minf(
			stats_component.get_stat(Stat.HEALTH) + heal_amount,
			stats_component.get_stat(Stat.HEALTH_MAX)
		)
		stats_component.set_stat(Stat.HEALTH, healed)
	if mana_amount > 0:
		var refilled: float = minf(
			stats_component.get_stat(Stat.MANA) + mana_amount,
			stats_component.get_stat(Stat.MANA_MAX)
		)
		stats_component.set_stat(Stat.MANA, refilled)
	if buff_stat != &"" and buff_amount != 0.0 and buff_duration_s > 0.0 and character is Player:
		BuffService.apply(character as Player, buff_stat, buff_amount, buff_duration_s)
	if character is Player:
		Inventory.remove_one_by_id(character.player_resource.inventory, get_meta(&"id"))
