class_name CharacterResource
extends Resource


@export var power_resources: Array[GameplayResource] = []

@export var class_name_id: StringName = &"knight"
@export var character_name: String

@export var character_sprite: SpriteFrames

# Base stats (defaults can be tuned per class)
@export var base_hp: float = 640.0
@export var base_mana: float = 0.0
@export var base_energy: float = 0.0
@export var base_ad: float = 60.0
@export var base_ap: float = 0.0
@export var base_armor: float = 32.0
@export var base_mr: float = 30.0
@export var base_as: float = 0.66
@export var base_move_speed: float = 330.0
@export var base_attack_range: float = 175.0
@export var base_crit_chance: float = 0.0
@export var base_crit_damage: float = 1.75
@export var base_ability_haste: float = 0.0

# Growth models (optional per stat)
@export var hp_growth: StatGrowthResource
@export var mana_growth: StatGrowthResource
@export var energy_growth: StatGrowthResource
@export var ad_growth: StatGrowthResource
@export var ap_growth: StatGrowthResource
@export var armor_growth: StatGrowthResource
@export var mr_growth: StatGrowthResource
@export var as_growth: StatGrowthResource

@export var passive_abilities: Array[AbilityResource]
@export var active_abilities: Array[AbilityResource]

@export var description: String = ""

# Possible character class evolution
# Example: knight -> [holy knight or dark knight]
@export var evolution: Array[CharacterResource]

# Build level-scaled base stats dictionary
func build_base_stats(level: int) -> Dictionary:
	var d: Dictionary = {}

	# health + health_max
	var hp_max: float = base_hp
	if hp_growth != null:
		hp_max = hp_growth.value_at_level(base_hp, level)
	d[StatsCatalog.HEALTH_MAX] = hp_max
	d[StatsCatalog.HEALTH] = hp_max

	# linear/multiplicative style stat growths
	d[StatsCatalog.AD] = ad_growth.value_at_level(base_ad, level) if ad_growth != null else base_ad
	d[StatsCatalog.AP] = ap_growth.value_at_level(base_ap, level) if ap_growth != null else base_ap
	d[StatsCatalog.ARMOR] = armor_growth.value_at_level(base_armor, level) if armor_growth != null else base_armor
	d[StatsCatalog.MR] = mr_growth.value_at_level(base_mr, level) if mr_growth != null else base_mr
	d[StatsCatalog.ATTACK_SPEED] = as_growth.value_at_level(base_as, level) if as_growth != null else base_as

	# Mostly static, but can swap to growth if needed.
	d[StatsCatalog.MOVE_SPEED] = base_move_speed
	d[StatsCatalog.ATTACK_RANGE] = base_attack_range
	d[StatsCatalog.CRIT_CHANCE] = base_crit_chance
	d[StatsCatalog.CRIT_DAMAGE] = base_crit_damage
	d[StatsCatalog.ABILITY_HASTE] = base_ability_haste
	return d
