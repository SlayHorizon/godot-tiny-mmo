class_name AttributeMap
## Maps spent attribute points to combat stats. Tuned for a level-20 cap (~60
## points total: 3 at creation + 3 per level). A dedicated ~40-50pt investment
## roughly DOUBLES the target stat — strong build identity, but skill + gear keep
## the power gap fair (≈2x, not 5x). Each level (3 pts) is a visible bump, so
## leveling always reads as progress.
##
## LIVE physical attributes (read by gameplay today): VITALITY, STRENGHT,
## AGILITY, DEFENSE — they cover the four stats combat actually consumes
## (HEALTH_MAX, AD, MOVE_SPEED, ARMOR).
##
## INTELLIGENCE (AP) and SPIRIT (mana/energy) feed the upcoming skill / magic
## weapon system. They're kept here so they're ready the moment that ships, but
## until then no combat code reads AP/mana — a point spent there is inert. Flag
## them as "coming soon" in the UI before launch so players don't sink points.


# --- Live physical attributes -------------------------------------------------

const VITALITY: Dictionary[StringName, float] = {
	Stat.HEALTH_MAX: 1.5,  # 60 all-in ≈ +90 HP (base 50 → 140, a real tank)
}

const STRENGHT: Dictionary[StringName, float] = {
	# Steep on purpose: with a low base AD (10), Strength is the main driver of
	# damage growth. 60 pts ≈ +36 AD, so a maxed STR build hits ~3-4× a fresh
	# level-1 — a strong, earned progression curve.
	Stat.AD: 0.6,
}

const AGILITY: Dictionary[StringName, float] = {
	# Move speed scales GENTLY on purpose — doubling it would break kiting/PvP.
	# ~60 pts ≈ +18 (90 → 108, +20%): a real edge, not a runaway.
	Stat.MOVE_SPEED: 0.3,
	Stat.ATTACK_SPEED: 0.015,  # activates once attack-speed gates weapon cooldowns
}

const DEFENSE: Dictionary[StringName, float] = {
	# Armor uses diminishing returns (100/(100+armor)) in take_damage, so stacking
	# this is self-balancing — it never makes you immortal. A little HP rides along
	# so Defense reads as a bruiser pick, not pure mitigation.
	Stat.ARMOR: 0.5,
	Stat.HEALTH_MAX: 0.5,
}

# --- Magic attributes (reserved for the skill / magic-weapon update) ----------

const INTELLIGENCE: Dictionary[StringName, float] = {
	Stat.AP: 0.4,
}

const SPIRIT: Dictionary[StringName, float] = {
	Stat.MANA_MAX: 1.0,
	Stat.ENERGY: 0.7,
}


static func attr_to_stats(attributes: Dictionary[StringName, int]) -> Dictionary[StringName, float]:
	var stats: Dictionary[StringName, float]
	for attribute_name: StringName in attributes:
		var amount: int = attributes[attribute_name]
		match attribute_name:
			&"vitality":
				add_attribute_to_stats(VITALITY, amount, stats)
			&"strenght":
				add_attribute_to_stats(STRENGHT, amount, stats)
			&"agility":
				add_attribute_to_stats(AGILITY, amount, stats)
			&"defense":
				add_attribute_to_stats(DEFENSE, amount, stats)
			&"intelligence":
				add_attribute_to_stats(INTELLIGENCE, amount, stats)
			&"spirit":
				add_attribute_to_stats(SPIRIT, amount, stats)
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
