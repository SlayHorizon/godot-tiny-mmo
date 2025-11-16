class_name GearItem
extends Item


@export var slot: ItemSlot
@export_range(0, 99, 1.0, "suffix:lvl") var required_level: int = 0

## Main Stats (Base stats)
@export var base_modifiers: Array[StatModifier]


func can_equip(player: Player) -> bool:
	if player.player_resource:
		return slot.is_unlocked_for(player.player_resource) and player.player_resource.level >= required_level
	return false


func on_equip(character: Character) -> void:
	for modifier: StatModifier in base_modifiers:
		character.ability_system_component.add_modifier(modifier)


func on_unequip(character: Character) -> void:
	for modifier: StatModifier in base_modifiers:
		character.ability_system_component.remove_modifier_by_id(modifier.runtime_id)
