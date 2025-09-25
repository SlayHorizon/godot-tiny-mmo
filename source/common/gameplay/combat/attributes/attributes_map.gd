class_name AttributeMap


const VITALITY: Dictionary[StringName, float] = {
	StatsCatalog.HEALTH: 5.0,
}

const STRENGHT: Dictionary[StringName, float] = {
	StatsCatalog.AD: 2.0,
}

const INTELLIGENCE: Dictionary[StringName, float] = {
	StatsCatalog.AP: 2.0,
}

const SPIRIT: Dictionary[StringName, float] = {
	StatsCatalog.MANA: 10.0,
	StatsCatalog.ENERGY: 10.0,
}

const MAGICAL_DEFENSE: Dictionary[StringName, float] = {
	StatsCatalog.MR: 1.5,
	StatsCatalog.HEALTH: 2.0,
}

const PHYSICAL_DEFENSE: Dictionary[StringName, float] = {
	StatsCatalog.ARMOR: 1.5,
	StatsCatalog.HEALTH: 2.0,
}


const AGILITY: Dictionary[StringName, float] = {
	StatsCatalog.MOVE_SPEED: 4,
	StatsCatalog.ATTACK_SPEED: 0.1
}

static func attr_to_stats(attributes: Dictionary[StringName, int]) -> Dictionary[StringName, float]:
	var stats: Dictionary[StringName, float]
	for attribute_name: StringName in attributes:
		var amount: int = attributes[attribute_name]
		match attribute_name:
			# Move to a proper mapper ?
			&"vitality":
				add_attribute_to_stats(VITALITY, amount, stats)
			&"strenght":
				add_attribute_to_stats(STRENGHT, amount, stats)
			&"intelligence":
				add_attribute_to_stats(INTELLIGENCE, amount, stats)
			&"spirit":
				add_attribute_to_stats(SPIRIT, amount, stats)
			&"agility":
				add_attribute_to_stats(AGILITY, amount, stats)
			#...
				#...
	return stats


static func add_attribute_to_stats(
	attribute: Dictionary[StringName, float],
	amount: int,
	stats: Dictionary[StringName, float]
) -> void:
	for stat_name: StringName in attribute:
		if stats.has(stat_name):
			stats[stat_name] += attribute[stat_name] * amount
		else:
			stats[stat_name] = attribute[stat_name] * amount
