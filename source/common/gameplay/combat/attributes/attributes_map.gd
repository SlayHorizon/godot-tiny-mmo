class_name AttributeMap
## Maps spent attribute points to combat stats. Tuned for a level-20 cap (~60
## points total: 3 at creation + 3 per level). A dedicated ~40-50pt investment
## roughly DOUBLES the target stat — strong build identity, but skill + gear keep
## the power gap fair (≈2x, not 5x). Each level (3 pts) is a visible bump, so
## leveling always reads as progress.
##
## All six attributes are LIVE: VITALITY (HP), STRENGHT (AD), AGILITY (speed),
## DEFENSE (armor, vs physical), INTELLIGENCE (AP — magic damage + heal power),
## SPIRIT (MR, vs magic). AP scales wand bolts/heals; MR mitigates magic damage
## in take_damage — the magic mirrors of AD/ARMOR. Mana/energy stay parked until
## the mana system ships (re-add to SPIRIT then).


# --- Live physical attributes -------------------------------------------------

const VITALITY: Dictionary[StringName, float] = {
	Stat.HEALTH_MAX: 2.0,  # 60 all-in ≈ +90 HP (base 50 → 140, a real tank)
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
	Stat.MOVE_SPEED: 0.5,
	# Haste shortens EVERY ability cooldown (attack speed for basics, CDR for
	# specials — one stat, see AbilityResource). 60 pts ≈ +15% faster actions.
	Stat.ABILITY_HASTE: 0.25,
}

const DEFENSE: Dictionary[StringName, float] = {
	# Armor uses diminishing returns (100/(100+armor)) in take_damage, so stacking
	# this is self-balancing — it never makes you immortal. A little HP rides along
	# so Defense reads as a bruiser pick, not pure mitigation.
	Stat.ARMOR: 0.5,
	Stat.MR: 0.5,
	Stat.HEALTH_MAX: 0.5,
}

# --- Magic attributes ----------------------------------------------------------

const INTELLIGENCE: Dictionary[StringName, float] = {
	# Mirrors STRENGHT: the main driver of MAGIC damage growth. Weapons grant the
	# base AP (wand +18), INT scales it — 60 pts ≈ +36 AP (×3 a fresh caster).
	# Also scales heal bolts (heal = AP × ratio), so INT is the support stat too.
	Stat.AP: 0.6,
}

const SPIRIT: Dictionary[StringName, float] = {
	# Mirrors DEFENSE on the magic side: MR mitigates magic damage in take_damage
	# with the same diminishing-returns curve as armor. Mana rides along so Spirit
	# is also the "use your specials more often" stat — the support/sustain pick.
	Stat.MANA_MAX: 1.0,
	# 60 pts ≈ +1.2/s on the 0.5 base — a dedicated Spirit build refills ~3× faster.
	Stat.MANA_REGEN: 0.1,
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
