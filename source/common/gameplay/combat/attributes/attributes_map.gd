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


static func attr_to_stats(attributes: Array[StringName]) -> Dictionary:
	var stats: Dictionary
	for attribute: StringName in attributes:
		match attribute:
			&"vitality":
				add_attribute_to_stats(VITALITY, 1, stats)
			&"strenght":
				add_attribute_to_stats(STRENGHT, 1, stats)
			#...
				#...
	return stats


static func add_attribute_to_stats(
	attribute: Dictionary[StringName, float],
	amount: int,
	stats: Dictionary
) -> void:
	for stat_name: StringName in attribute:
		if stats.has(stat_name):
			stats[stat_name] += attribute[stat_name] * amount
		else:
			stats[stat_name] = attribute[stat_name] * amount
