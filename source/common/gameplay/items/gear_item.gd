class_name GearItem
extends Item


@export var slot: ItemSlot
@export_range(0, 99, 1.0, "suffix:lvl") var required_level: int = 0

## Main Stats (Base stats)
@export var base_modifiers: Array[StatModifier]


func stat_lines() -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	for modifier: StatModifier in base_modifiers:
		if modifier == null or is_zero_approx(modifier.value):
			continue
		lines.append({"text": _format_modifier(modifier), "stat": StringName(modifier.stat_name)})
	if required_level > 0:
		lines.append({"text": "Requires level %d" % required_level, "kind": &"level"})
	return lines


## "+5 Attack Damage" / "-3 Armor". Integer when whole, else one decimal.
static func _format_modifier(modifier: StatModifier) -> String:
	var value: float = modifier.value
	var number: String = ("%+d" % int(value)) if is_equal_approx(value, roundf(value)) else ("%+.1f" % value)
	return "%s %s" % [number, Stat.display_name(modifier.stat_name)]


func can_equip(player: Player) -> bool:
	if player.player_resource:
		return slot.is_unlocked_for(player.player_resource) and player.player_resource.level >= required_level
	return false


func equip(character: Character) -> void:
	if not character.multiplayer.is_server():
		# Client side logic - visual
		return
	for modifier: StatModifier in base_modifiers:
		character.stats_component.modify_stat(
			modifier.stat_name, modifier.value
		)


func unequip(character: Character) -> void:
	if not character.multiplayer.is_server():
		# Client side logic - visual
		return
	for modifier: StatModifier in base_modifiers:
		character.stats_component.modify_stat(
			modifier.stat_name, modifier.value * -1
		)
