class_name ConsumableItem
extends Item


## Flat health restored on use. 0 = this consumable doesn't heal.
## Prototype-simple effect; can later move to a data-driven GameplayEffect list.
@export var heal_amount: int
@export var shared_cooldown_ms: int = 1500
@export var cooldown_category: StringName = &"potion"
## initial charges per single copy if 1 can use the potion one time, if 2 can use the potion 2 times for example.
@export var default_charges: int = 1


func can_use(character: Character) -> bool:
	if character == null:
		return false
	if heal_amount > 0:
		return character.stats_component.get_stat(Stat.HEALTH) < character.stats_component.get_stat(Stat.HEALTH_MAX)
	return false


## Applies the consumable's effect. Returns true if something actually happened
## (so the caller knows whether to spend a charge / remove it from the bag).
func on_use(character: Character) -> void:
	if heal_amount > 0:
		var stats_component: StatsComponent = character.stats_component
		var healed: float = minf(
			stats_component.get_stat(Stat.HEALTH) + heal_amount,
			stats_component.get_stat(Stat.HEALTH_MAX)
		)
		stats_component.set_stat(Stat.HEALTH, healed)
	if character is Player:
		Inventory.remove_one_by_id(character.player_resource.inventory, get_meta(&"id"))
