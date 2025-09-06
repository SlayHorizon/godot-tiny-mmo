class_name ItemBehavior
extends Resource


## If NPC needs to handle an equipment, we don't use this check, we directly equip it.
@warning_ignore("unused_parameter")
func can_equip(player: Player) -> bool:
	return false


@warning_ignore("unused_parameter")
func on_equip(character: Character, item: Item) -> void:
	pass


@warning_ignore("unused_parameter")
func on_unequip(character: Character, item: Item) -> void:
	pass


@warning_ignore("unused_parameter")
func on_use(asc: AbilitySystemComponent, item: Item) -> bool:
	return false
