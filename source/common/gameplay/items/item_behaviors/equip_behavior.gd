class_name EquipBehavior
extends ItemBehavior


enum Slots {
	BOOTS,
	RING,
	WEAPON
	#...
}

	#Weapon
	#Helmet
	#Breastplate
	#Pants
	#Gloves
	#Shoes
	#Necklace
	#Bracers
	#Ring
	#Seal (Available at level 50)
	#Talisman (Available at level 55)
	#Relic (Available at level 60)

@export var slot: Slots
## Main Stats (Base stats)
@export var base_modifiers: Array[StatModifier]
## Define the growth of an attribute depending of the level.
## (Additionnal Attributes by level)
@export var base_growth: Array[StatGrowthResource]
@export var base_effects: Array[GameplayEffect]
@export_range(0, 30, 1.0, "suffix:lvl") var required_level: int = 0


## Set when loaded for the first time.
## Tracked in ContentRegistryHub.
var id: int
## Level of enhancement. Used by StatGrowth.
var level: int
## From 0 to 100.
## When 0 the item unusable, can be repaired.
var durability: int
## From 0% to 100% affects main stats.
## 100% = All  base stats given.
## 50% = Half base stats given.
var calibration: int


func can_equip(player: Player) -> bool:
	if player.player_resource:
		if player.player_resource.level >= required_level:
			return true
	return false


func on_equip(character: Character, item: Item) -> void:
	for modifier: StatModifier in base_modifiers:
		character.ability_system_component.add_modifier(modifier)
	for effect: GameplayEffect in base_effects:
		character.ability_system_component.add_effect(effect)


func on_unequip(character: Character, item: Item) -> void:
	for modifier: StatModifier in base_modifiers:
		character.ability_system_component.remove_modifier_by_id(modifier.runtime_id)
	for effect: GameplayEffect in base_effects:
		character.ability_system_component.remove_effect_by_name(effect.name_id)


## Build item from delta data.
func build_from_data(data: Dictionary) -> EquipBehavior:
	var s: EquipBehavior = self.duplicate(false)
	level = data.get("level", 1)
	durability = data.get("durability", 75)
	calibration = data.get("calibration", 50)
	return s


## Used mainly by server but could be used by client
## to cache it later.
func save_state() -> Dictionary:
	return {
		id: {
			"level": level,
			"durability": durability,
			"calibration": calibration,
		}
	}
