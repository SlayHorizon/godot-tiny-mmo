class_name AttributeMap


const VITALITY: Dictionary[StringName, float] = {
	Stat.HEALTH: 5.0,
	Stat.HEALTH_MAX: 5.0
}

const STRENGHT: Dictionary[StringName, float] = {
	Stat.AD: 2.0,
}

const INTELLIGENCE: Dictionary[StringName, float] = {
	Stat.AP: 2.0,
}

const SPIRIT: Dictionary[StringName, float] = {
	Stat.MANA: 10.0,
	Stat.MANA_MAX: 10.0,
	Stat.ENERGY: 10.0,
}

const MAGICAL_DEFENSE: Dictionary[StringName, float] = {
	Stat.MR: 1.5,
	Stat.HEALTH: 2.0,
	Stat.HEALTH_MAX: 2.0
}

const PHYSICAL_DEFENSE: Dictionary[StringName, float] = {
	Stat.ARMOR: 1.5,
	Stat.HEALTH: 2.0,
	Stat.HEALTH_MAX: 2.0
}


const CONDITION: Dictionary[StringName, float] = {
	&"tenacity": 3.0,#Stat.TENACITY
	Stat.ARMOR: 1.0,
	Stat.MR: 1.0,
	Stat.HEALTH: 2.0,
	Stat.HEALTH_MAX: 2.0
}


const AGILITY: Dictionary[StringName, float] = {
	Stat.MOVE_SPEED: 4,
	Stat.ATTACK_SPEED: 0.1
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
